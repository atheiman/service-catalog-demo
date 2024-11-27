######
### This content should be defined in all products
######
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
# Service Catalog user-supplied tags will be provided in this variable
variable "default_tags_json" {
  default = {}
}
provider "aws" {
  default_tags {
    tags = jsondecode(var.default_tags_json)
  }
}

######
### Rest of content is custom for this product
######

locals {
  bucket_policy_statement_read = {
    Effect = "Allow"
    Principal = {
      AWS = compact([for a in split(",", var.read_principal_arns_csv) : trimspace(a)])
    }
    Action = [
      "s3:Get*",
      "s3:List*",
    ]
    Resource = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*",
    ]
  }
  bucket_policy_statement_write = {
    Effect = "Allow"
    Principal = {
      AWS = compact([for a in split(",", var.write_principal_arns_csv) : trimspace(a)])
    }
    Action = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
    ]
    Resource = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*",
    ]
  }
  bucket_policy_statements = [
    for s in [local.bucket_policy_statement_read, local.bucket_policy_statement_write] :
    s
    if length(s.Principal.AWS) > 0
  ]
}

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_name_prefix
  force_destroy = tobool(lower(tostring(var.force_destroy)))
}

resource "aws_s3_bucket_policy" "policy" {
  count  = length(local.bucket_policy_statements) > 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.bucket_policy_statements
  })
}

output "bucket_name" {
  value = aws_s3_bucket.bucket.id
}

output "bucket_arn" {
  value = aws_s3_bucket.bucket.arn
}

output "bucket_tf_resource" {
  value = aws_s3_bucket.bucket
}
