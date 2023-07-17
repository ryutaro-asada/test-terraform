terraform {
  required_version = ">= 1.2.0"
  backend "s3" {
    bucket  = "tera-tera-state"
    region  = "ap-northeast-1"
    key     = "test.tfstate"
    encrypt = true
  }
}
