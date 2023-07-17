module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"


  azs = [
    "ap-northeast-1a",
    "ap-northeast-1c",
  ]
  private_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24",
  ]
  public_subnets = [
    "10.0.101.0/24",
    "10.0.102.0/24",
  ]

  # One NAT Gateway per availability zone
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
