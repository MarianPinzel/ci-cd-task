terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Simple local backend by default so the task can be run without extra
  # setup. For real use, replace with an S3 + DynamoDB remote backend.
  # backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
