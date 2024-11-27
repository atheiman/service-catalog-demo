locals {
  tf_products_dirname = "terraform-products"
  tf_products_names = distinct([
    for f in fileset("${path.module}/${local.tf_products_dirname}", "*/*/*.{tf,tf.json}") :
    split("/", f)[0]
  ])
  tf_products_version_dir_names = {
    for product_name in local.tf_products_names :
    product_name => distinct([
      for f in fileset("${path.module}/${local.tf_products_dirname}/${product_name}", "*/*.{tf,tf.json}") :
      split("/", f)[0]
    ])
  }

  # Use this map to override any default settings for products. This map is merged into `local.tf_products`.
  tf_products_customizations = {
    tf-s3-bucket = {
      description = "Creates an S3 bucket using Terraform external provisioning engine"
    }
  }

  # Example:
  # {
  #   "my-product" = {
  #     "customization_key" = "customization defined above"
  #     "versions" = {
  #       "v0.1" = {
  #         "module_path" = "terraform-products/my-product/v0.1"
  #       }
  #       "v0.2" = {
  #         "module_path" = "terraform-products/my-product/v0.2"
  #       }
  #     }
  #   }
  # }
  tf_products = {
    for product_name, version_dir_names in local.tf_products_version_dir_names :
    product_name => merge(
      {
        versions = {
          for dir_name in version_dir_names :
          dir_name => {
            module_path = join("/", [local.tf_products_dirname, product_name, dir_name])
          }
        }
      },
      try(local.tf_products_customizations[product_name], {})
    )
  }
}

output "tf_products" {
  value = local.tf_products
}

data "archive_file" "tf_empty_product" {
  type        = "zip"
  output_path = "${path.module}/tf-empty-product.zip"

  source {
    filename = "variables.tf.json"
    content  = "{}"
  }

  source {
    filename = "main.tf"
    content  = <<-EOF
      terraform {
        required_providers {
          aws = {
            source  = "hashicorp/aws"
            version = ">= 5.0"
          }
        }
      }
    EOF
  }
}

resource "aws_s3_object" "tf_empty_product" {
  bucket = aws_s3_bucket.product_artifacts.id
  key    = "${local.tf_products_dirname}/${basename(data.archive_file.tf_empty_product.output_path)}"
  source = data.archive_file.tf_empty_product.output_path
}

resource "aws_servicecatalog_product" "tf_products" {
  for_each            = local.tf_products
  name                = each.key
  owner               = try(each.value["owner"], aws_servicecatalog_portfolio.portfolio.provider_name)
  description         = try(each.value["description"], null)
  distributor         = try(each.value["distributor"], null)
  support_description = try(each.value["support_description"], null)
  support_email       = try(each.value["support_email"], "sc-product-help@example.com")
  support_url         = try(each.value["support_url"], "https://example.internal/sc-product-help")
  type                = "EXTERNAL"

  # Exactly 1 version must be published using aws_servicecatalog_product. Use an artifact with no resources. Deactivate
  # or delete this version via ServiceCatalog console after deploying a new product. Additional versions will be
  # published below using "tf-product-version" module.
  provisioning_artifact_parameters {
    name                        = "Initial-Release-Do-Not-Use"
    description                 = "INITIAL RELEASE - DO NOT USE - PORTFOLIO ADMINISTRATOR SHOULD MANUALLY DELETE THIS VERSION"
    disable_template_validation = true
    type                        = "EXTERNAL"
    template_url                = "https://${aws_s3_bucket.product_artifacts.bucket_regional_domain_name}/${aws_s3_object.tf_empty_product.key}"
  }
}

resource "aws_servicecatalog_product_portfolio_association" "tf_products" {
  for_each     = aws_servicecatalog_product.tf_products
  portfolio_id = aws_servicecatalog_portfolio.portfolio.id
  product_id   = each.value.id
}

# This uses the same launch constraint on all products. Different launch constraint can be applied to
# different products if needed.
resource "aws_servicecatalog_constraint" "tf_products_launch_constraint" {
  # launch constraint role must be created by cloudformation before launch constraint
  depends_on = [aws_cloudformation_stack_set_instance.svc_ctlg_org, aws_cloudformation_stack.svc_ctlg]

  # aws_servicecatalog_product_portfolio_association must be created before creating constraints
  for_each = aws_servicecatalog_product_portfolio_association.tf_products

  type         = "LAUNCH"
  description  = "Launch constraint - use role ${local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRoleName} to provision products"
  portfolio_id = each.value.portfolio_id
  product_id   = each.value.product_id

  # https://docs.aws.amazon.com/servicecatalog/latest/dg/API_CreateConstraint.html#servicecatalog-CreateConstraint-request-Parameters
  parameters = jsonencode({
    LocalRoleName = local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRoleName
  })
}

module "tf_product_version" {
  # {
  #   "my-product:v0.1" = {
  #     "product_name" = "my-product"
  #     "version_name" = "v0.1"
  #     "version" = {
  #       "module_path" = "terraform-products/my-product/v0.1"
  #     }
  #   }
  #   "my-product:v0.2" = {
  #     "product_name" = "my-product"
  #     "version_name" = "v0.2"
  #     "version" = {
  #       "module_path" = "terraform-products/my-product/v0.2"
  #     }
  #   }
  # }
  for_each = merge(
    flatten(
      [
        for product_name, product in local.tf_products :
        {
          for version_name, version in product["versions"] :
          "${product_name}:${version_name}" => {
            product_name = product_name
            version_name = version_name
            version      = version
          }
        }
      ]
    )...
  )

  source       = "./modules/tf-product-version"
  bucket       = aws_s3_bucket.product_artifacts
  s3_key       = "${each.value.version.module_path}.zip"
  sc_product   = aws_servicecatalog_product.tf_products[each.value.product_name]
  source_dir   = "${path.module}/${each.value.version.module_path}"
  version_name = each.value.version_name
}
