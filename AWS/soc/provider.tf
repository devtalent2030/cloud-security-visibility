terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3"
    }
  }
}

# Management / Root account provider (run Terraform here)
provider "aws" {
  region = var.region
}

# Delegated admin account provider (Auth) where Security Hub runs
provider "aws" {
  alias  = "delegated"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.delegated_admin_account}:role/${var.cross_account_role}"
  }
}
