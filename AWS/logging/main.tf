# Look up org metadata (for bucket policy paths)
data "aws_organizations_organization" "org" {}

############################################
# S3 bucket in LOGGING (Auth) account
############################################
resource "aws_s3_bucket" "centralized_audit_logs" {
  provider = aws.logging
  bucket   = var.bucket_name
}

# Block all public access (belt & suspenders)
resource "aws_s3_bucket_public_access_block" "pab" {
  provider                = aws.logging
  bucket                  = aws_s3_bucket.centralized_audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption (SSE-S3). You can swap to KMS later.
resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  provider = aws.logging
  bucket   = aws_s3_bucket.centralized_audit_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Optional lifecycle to control costs (keep 30d then transition; tweak as you like)
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  provider = aws.logging
  bucket   = aws_s3_bucket.centralized_audit_logs.id

  rule {
    id     = "transition-logs"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "GLACIER_IR" # cost-conscious portfolio demo
    }
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER_IR"
    }
  }
}

# Bucket policy: allow only CloudTrail to write org/account logs with bucket-owner control
data "aws_caller_identity" "mgmt" {}

locals {
  bucket_arn            = aws_s3_bucket.centralized_audit_logs.arn
  org_id                = data.aws_organizations_organization.org.id
  logging_account_id    = var.logging_account_id
  cloudtrail_principal  = "cloudtrail.amazonaws.com"
}

resource "aws_s3_bucket_policy" "cloudtrail_access" {
  provider = aws.logging
  bucket = aws_s3_bucket.centralized_audit_logs.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      # 1) Let CloudTrail check the bucket ACL
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.centralized_audit_logs.arn
      },

      # 2) Allow CloudTrail to write log files for the management account
      #    (CloudTrail validates this exact PutObject with bucket-owner-full-control)
      {
        Sid       = "AWSCloudTrailWriteMgmt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.centralized_audit_logs.arn}/AWSLogs/${data.aws_caller_identity.mgmt.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },

      # 3) Allow org-trail deliveries across the organization scope
      #    (some org-trail validations expect the org-id prefix allowance)
      {
        Sid       = "AWSCloudTrailWriteOrg"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.centralized_audit_logs.arn}/AWSLogs/${data.aws_organizations_organization.org.id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}
############################################
# Organization Trail (Management account)
############################################
resource "aws_cloudtrail" "organizational_trail" {
  name                          = "organizational_trail"
  s3_bucket_name                = aws_s3_bucket.centralized_audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true

  # Keep this lean & cheap for portfolio: management events only
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    # No data_resource blocks => no data events (cost saver)
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_access]
}

output "central_bucket" {
  value = aws_s3_bucket.centralized_audit_logs.id
}

output "trail_name" {
  value = aws_cloudtrail.organizational_trail.name
}
