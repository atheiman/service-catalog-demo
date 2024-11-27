terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "bucket" {}
variable "s3_key" { type = string }
variable "sc_product" {}
variable "source_file_path" { type = string }
variable "version_name" { type = string }

locals {
  # Attempt to load CloudFormation template Metadata section
  #   https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/metadata-section-structure.html
  cfn_metadata = try(yamldecode(file(var.source_file_path)).Metadata, {})
}

resource "aws_s3_object" "this" {
  bucket = var.bucket.id
  key    = var.s3_key
  source = var.source_file_path

  lifecycle {
    ignore_changes = [
      # Template change triggers replace. DO NOT REPLACE PRODUCT VERSIONS. Create new product versions instead.
      bucket,
      key,
      source,
      etag,
      source_hash,
    ]
  }
}

# Terraform sets some attributes in an UpdateProvisioningArtifact API request immediately after creating a product
# version. Often the product version does not exist yet, and this error can be safely retried in a new Terraform apply:
#   Error: updating Service Catalog Provisioning Artifact (...): operation error Service Catalog:
#          UpdateProvisioningArtifact, https response error StatusCode: 400, RequestID: ...,
#          ResourceNotFoundException: ProvisioningArtifact ... not found.
resource "aws_servicecatalog_provisioning_artifact" "this" {
  name         = var.version_name
  product_id   = var.sc_product.id
  type         = "CLOUD_FORMATION_TEMPLATE"
  template_url = "https://${var.bucket.bucket_regional_domain_name}/${aws_s3_object.this.key}"
  guidance     = try(local.cfn_metadata.ServiceCatalog.ProductVersion.Guidance, null)
  description  = try(local.cfn_metadata.ServiceCatalog.ProductVersion.Description, null)

  lifecycle {
    ignore_changes = [
      # Template change triggers replace. DO NOT REPLACE PRODUCT VERSIONS. Create new product versions instead.
      template_url,
    ]
  }
}

output "provisioning_artifact" {
  value = aws_servicecatalog_provisioning_artifact.this
}
