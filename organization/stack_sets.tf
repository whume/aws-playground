resource "aws_cloudformation_stack_set" "terraform" {
  name             = "terraform-default-stackset"
  description      = "StackSet that deploys resources to start using terraform in all accounts"
  template_body    = file("./account_templates/terraform-defaults.json")

  capabilities            = ["CAPABILITY_IAM"]
  permission_model        = "SERVICE_MANAGED"
  auto_deployment {
    enabled = true
  }
}

resource "aws_cloudformation_stack_set_instance" "terraform" {
  region = "us-east-1"
  stack_set_name = aws_cloudformation_stack_set.terraform.name
  deployment_targets {
    organizational_unit_ids = [aws_organizations_organization.org.roots[0].id]
  }
}

resource "aws_cloudformation_stack" "terraform-mgmt" {
  name = "terraform-default"
  template_body = file("./account_templates/terraform-defaults.json")
  capabilities = ["CAPABILITY_NAMED_IAM"]
}