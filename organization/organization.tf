import {
  to = aws_organizations_organization.org
  id = "o-1naruu1w9c"
}

resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "controltower.amazonaws.com",
    "guardduty.amazonaws.com",
    "sso.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
  ]
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY"
  ]
  feature_set = "ALL"
}

import {
  to = aws_organizations_organizational_unit.security
  id = "ou-wual-boby66op"
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

import {
  to = aws_organizations_organizational_unit.tech
  id = "ou-wual-2g63jyq1"
}
resource "aws_organizations_organizational_unit" "tech" {
  name      = "Tech"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "suspended" {
  name      = "Suspended"
  parent_id = aws_organizations_organization.org.roots[0].id
}