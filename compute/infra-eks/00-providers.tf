provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      creator = "terraform"
      repo    = "github.com/whume/aws-playground"
      stack   = "infra-eks"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}


provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

terraform {
  backend "s3" {
    bucket = "tf-state-176207359176"
    key    = "compute/infra-eks/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_availability_zones" "available" {}
data "aws_ecrpublic_authorization_token" "token" {}

# AWS Load Balancer Controller

module "load_balancer_controller" {
  source = "git::https://github.com/DNXLabs/terraform-aws-eks-lb-controller.git"

  helm_chart_version               = "1.7.2"
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
  cluster_name                     = module.eks.cluster_name
  settings                         = {
    region: "us-east-1"
    vpcId: data.terraform_remote_state.infra.outputs.infra_vpc_id
  }
}