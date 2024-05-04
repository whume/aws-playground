resource "aws_cloudformation_stack_set" "terraform" {
  name          = "terraform-default-stackset"
  description   = "StackSet that deploys resources to start using terraform in all accounts"
  template_body = file("./account_templates/terraform-defaults.json")

  capabilities     = ["CAPABILITY_IAM"]
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled = true
  }
  lifecycle {
    ignore_changes = [
      administration_role_arn
    ]
  }
}

resource "aws_cloudformation_stack_set_instance" "terraform" {
  region         = "us-east-1"
  stack_set_name = aws_cloudformation_stack_set.terraform.name
  deployment_targets {
    organizational_unit_ids = [aws_organizations_organization.org.roots[0].id]
  }
}

resource "aws_cloudformation_stack" "terraform-mgmt" {
  name          = "terraform-default"
  template_body = file("./account_templates/terraform-defaults.json")
  capabilities  = ["CAPABILITY_NAMED_IAM"]
}

resource "aws_cloudformation_stack" "github-actions" {
  name = "github-actions"
  parameters = {
    GithubActionsThumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1,1c58a3a8518e8759bf075b76b750d4f2df264fcd"
    SubjectClaimFilters     = "repo:whume/aws-playground:*"
    ManagedPolicyARNs       = "arn:aws:iam::aws:policy/AdministratorAccess"
  }
  template_body = file("./account_templates/github-actions.json")
  capabilities  = ["CAPABILITY_NAMED_IAM"]
}

resource "aws_cloudformation_stack_set" "github-actions" {
  name          = "github-actions-stackset"
  description   = "StackSet that deploys resources to start using github-actions in all accounts"
  template_body = file("./account_templates/github-actions.json")
  parameters = {
    GithubActionsThumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1,1c58a3a8518e8759bf075b76b750d4f2df264fcd"
    SubjectClaimFilters     = "repo:whume/aws-playground:*"
    ManagedPolicyARNs       = "arn:aws:iam::aws:policy/AdministratorAccess"
  }
  capabilities     = ["CAPABILITY_IAM"]
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled = true
  }
  lifecycle {
    ignore_changes = [
      administration_role_arn
    ]
  }
}

resource "aws_cloudformation_stack_set_instance" "github-actions" {
  region         = "us-east-1"
  stack_set_name = aws_cloudformation_stack_set.github-actions.name
  deployment_targets {
    organizational_unit_ids = [aws_organizations_organization.org.roots[0].id]
  }
}