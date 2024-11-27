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
variable "source_dir" {
  type = string

  # Verify variables.tf.json exists and is valid json
  validation {
    condition = try(
      startswith(jsonencode(jsondecode(file("${var.source_dir}/variables.tf.json"))), "{"),
      false,
    )
    error_message = "Validation error creating terraform product: Could not parse json file \"${var.source_dir}/variables.tf.json\". This file must contain valid tf.json format and declare any variables the user should customize when launching the product. If no variables are required for the product, the file contents should be an empty object: {}"
  }
}
variable "version_name" { type = string }

locals {
  metadata = try(yamldecode(file("${var.source_dir}/metadata.yml")), {})
}

data "archive_file" "this" {
  type = "zip"
  # Save the archive with into path.root and with a unique name so multiple terraform projects and
  # regions and modules can utilize this module simultaneously
  output_path = "${path.root}/tf-product-${var.sc_product.id}-${var.version_name}.zip"
  # Specifying output_file_mode helps produce consistent zip archive contents on linux and windows
  output_file_mode = "0644"
  source_dir       = var.source_dir
}

resource "aws_s3_object" "this" {
  bucket = var.bucket.id
  key    = var.s3_key
  source = data.archive_file.this.output_path

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
  name                        = var.version_name
  product_id                  = var.sc_product.id
  type                        = "EXTERNAL"
  disable_template_validation = true # required for EXTERNAL product type
  template_url                = "https://${var.bucket.bucket_regional_domain_name}/${aws_s3_object.this.key}"
  guidance                    = try(local.metadata.ServiceCatalog.ProductVersion.Guidance, null)
  description                 = try(local.metadata.ServiceCatalog.ProductVersion.Description, null)

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
