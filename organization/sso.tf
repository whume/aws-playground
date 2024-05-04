data "aws_organizations_organization" "current" {}

data "aws_organizations_organizational_units" "all_ous" {
  parent_id = data.aws_organizations_organization.current.roots[0].id
}

data "aws_organizations_organizational_unit_child_accounts" "security_accounts" {
  parent_id = local.security_ou_id[0]
}

locals {
  all_accounts = [
    for a in data.aws_organizations_organization.current.accounts :
    a.id
    if a.status == "ACTIVE"
  ]
  security_ou_id = [
    for ou in data.aws_organizations_organizational_units.all_ous.children : ou.id
    if ou.name == "Security"
  ]
  security_accounts = [
    for a in data.aws_organizations_organizational_unit_child_accounts.security_accounts.accounts : a.id
    if a.status == "ACTIVE"
  ]

}

module "aws-iam-identity-center" {
  source = "aws-ia/iam-identity-center/aws"

  permission_sets = {
    AdministratorAccess = {
      description          = "Provides AWS full access permissions.",
      session_duration     = "PT12H",
      aws_managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      tags                 = { ManagedBy = "Terraform" }
    },
    ViewOnlyAccess = {
      description          = "Provides AWS view only permissions.",
      session_duration     = "PT3H",
      aws_managed_policies = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
      tags                 = { ManagedBy = "Terraform" }
    },
  }

  account_assignments = {
    Admin : {
      principal_name  = "AWS"
      principal_type  = "GROUP"
      permission_sets = ["AdministratorAccess"]
      account_ids     = local.all_accounts
    },
    Audit : {
      principal_name  = "AWS"
      principal_type  = "GROUP"
      permission_sets = ["ViewOnlyAccess"]
      account_ids     = local.security_accounts
    },
  }
}