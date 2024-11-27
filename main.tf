terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      TerraformProjectDir = basename(abspath(path.module))
    }
  }
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

locals {
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.name
  acct_id   = data.aws_caller_identity.current.account_id
  org       = data.aws_organizations_organization.current
}
