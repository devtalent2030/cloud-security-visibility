variable "delegated_admin_account" {
  type        = string
  description = "Account ID that will be the Security Hub delegated admin (Auth)"
}

variable "cross_account_role" {
  type        = string
  description = "Role name to assume in the delegated admin account (e.g., OrganizationAccountAccessRole)"
}

variable "region" {
  type        = string
  description = "Home region to enable Security Hub in first"
  default     = "us-east-1"
}
