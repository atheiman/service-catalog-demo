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
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_name_prefix
  force_destroy = var.force_destroy
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
