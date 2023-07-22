terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
  }
  required_version = ">= 1.2.0"
}

module "karpenter" {
  source       = "terraform-aws-modules/eks/aws//modules/karpenter"
  version      = "19.15.3"
  cluster_name = module.eks_cluster.cluster_name
  # spot instance 使う予定なし。
  enable_spot_termination         = false
  irsa_oidc_provider_arn          = module.eks_cluster.oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  # Since Karpenter is running on an EKS Managed Node group,
  # we can re-use the role that was created for the node group
  create_iam_role = false
  iam_role_arn    = module.eks_cluster.eks_managed_node_groups["systems"].iam_role_arn
}


resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  # ドキュメントだと書いてあったが多分不要
  #repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart   = "karpenter"
  version = "v0.23.0"

  set {
    name  = "settings.aws.clusterName"
    value = module.eks_cluster.cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks_cluster.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.irsa_arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter.instance_profile_name
  }

  # spot instance 使う予定なし。
  #set {
  #  name  = "settings.aws.interruptionQueueName"
  #  value = module.karpenter.queue_name
  #}
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: systems
    spec:
      providerRef:
        name: systems
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
          # values: ["spot"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["4", "8"]
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["ap-northeast-1a", "ap-northeast-1c"]  
        - key: "eks.amazonaws.com/nodegroup" 
          operator: In
          values: ["systems"]  
      limits:
        resources:
          cpu: 0
      # Enables consolidation which attempts to reduce cluster cost by both removing un-needed nodes and down-sizing those
      # that can't be removed.  Mutually exclusive with the ttlSecondsAfterEmpty parameter.
      #ttlSecondsAfterEmpty: 30
      consolidation:
        enabled: true

      # If omitted, the feature is disabled and nodes will never expire.  If set to less time than it requires for a node
      # to become ready, the node may expire before any pods successfully start.
      ttlSecondsUntilExpired: 120 # 30 Days = 60 * 60 * 24 * 30 Seconds;
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}


resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: systems
    spec:
      subnetSelector:
        karpenter.sh/discovery: "${module.eks_cluster.cluster_name}"
      securityGroupSelector:
        karpenter.sh/discovery: "${module.eks_cluster.cluster_name}"
      tags:
        karpenter.sh/discovery: "${module.eks_cluster.cluster_name}"
  YAML
  depends_on = [
    helm_release.karpenter
  ]
}

