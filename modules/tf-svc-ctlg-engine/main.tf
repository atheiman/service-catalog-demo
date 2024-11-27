# https://docs.aws.amazon.com/servicecatalog/latest/adminguide/external-engine.html

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "svc_ctlg_launch_role_path" {
  type = string
}
variable "svc_ctlg_launch_role_name" {
  type = string
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
