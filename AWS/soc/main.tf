#############################################
# 1) Org setup: allow Security Hub + delegate admin
#############################################

# NOTE: Manage this resource ONLY in one place for your org.
# You already have an Organization, so we keep it here for documentation
# but tell Terraform not to try and re-create or change it.
resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "ram.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "config.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com"
  ]
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_securityhub_organization_admin_account" "delegate" {
  depends_on       = [aws_organizations_organization.this]
  admin_account_id = var.delegated_admin_account
}

#############################################
# 2) Enable Security Hub in delegated admin (Auth) + standards
#############################################

# Turn on Security Hub in Auth (home region)
resource "aws_securityhub_account" "enable_in_admin" {
  provider = aws.delegated
}

# Subscribe to standards (AFSBP + CIS v1.4.0)
locals {
  standards_arns = {
    afsbp = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
    cis14 = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  }
}

resource "aws_securityhub_standards_subscription" "standards" {
  for_each      = local.standards_arns
  provider      = aws.delegated
  standards_arn = each.value
  depends_on    = [aws_securityhub_account.enable_in_admin]
}

#############################################
# 3) Organization-wide auto-enroll for new accounts
#############################################
#############################################
# 3) Organization-wide auto-enroll for new accounts
#############################################
resource "aws_securityhub_organization_configuration" "org_auto" {
  provider    = aws.delegated   # ← run from the delegated admin (Auth)
  auto_enable = true
  depends_on  = [
    aws_securityhub_organization_admin_account.delegate,
    aws_securityhub_account.enable_in_admin
  ]
}
