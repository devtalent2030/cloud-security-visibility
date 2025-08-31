variable "region" {
  type        = string
  description = "Home region for the org trail & bucket"
  default     = "us-east-1"
}

variable "logging_account_id" {
  type        = string
  description = "Account ID where the centralized S3 bucket lives (Auth for portfolio)"
}

variable "cross_account_role" {
  type        = string
  description = "Role name assumable in the logging account (e.g., CrossAccount-SecurityOps)"
}

variable "bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name for CloudTrail audit logs"
}
