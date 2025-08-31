terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3"
    }
  }
}

# Management / Root account provider (you run Terraform here)
provider "aws" {
  region = var.region
  profile = "terraform-provisioner"  # <— add this
}

# Logging account provider (Auth) via cross-account role
provider "aws" {
  alias  = "logging"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.logging_account_id}:role/${var.cross_account_role}"
  }
}
