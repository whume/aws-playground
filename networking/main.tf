
data "aws_availability_zones" "available" {}

locals {
  region = "us-east-1"
  vpc_cidr = "10.130.0.0/16"
  vpc_cidr_2 = "10.134.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
}

################################################################################
# VPC Module
################################################################################

module "infra" {
  source = "terraform-aws-modules/vpc/aws"

  name = "infra"
  cidr = local.vpc_cidr

  azs                 = local.azs
  private_subnets     = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 4)]
  public_subnets      = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 128)]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dhcp_options              = true

  enable_flow_log                      = false
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false
}

module "apps" {
  source = "terraform-aws-modules/vpc/aws"

  name = "apps"
  cidr = local.vpc_cidr_2

  azs                 = local.azs
  private_subnets     = [for k, v in local.azs : cidrsubnet(local.vpc_cidr_2, 6, k + 4)]
  public_subnets      = [for k, v in local.azs : cidrsubnet(local.vpc_cidr_2, 8, k + 128)]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dhcp_options              = true

  enable_flow_log                      = false
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false
}
