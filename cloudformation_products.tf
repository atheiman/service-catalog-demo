locals {
  cfn_products_dirname = "cloudformation-products"
  cfn_products_names   = distinct([for f in fileset("${path.module}/${local.cfn_products_dirname}", "*/*.{yml,yaml,json}") : split("/", f)[0]])
  cfn_products_version_file_names = {
    for product_name in local.cfn_products_names :
    product_name => fileset("${path.module}/${local.cfn_products_dirname}/${product_name}", "*.{yml,yaml,json}")
  }

  # Use this map to override any default settings for products. This map is merged into `local.cfn_products`.
  cfn_products_customizations = {
    s3-bucket = {
      description = "Create an S3 bucket"
    }
    ec2-instance = {
      description = "Create an EC2 instance"
    }
  }

  # Example:
  # {
  #   "my-product" = {
  #     "customization_key" = "customization defined above"
  #     "versions" = {
  #       "v0.1" = {
  #         "file_name" = "v0.1.yml"
  #         "file_path" = "cloudformation-products/my-product/v0.1.yml"
  #       }
  #       "v0.2" = {
  #         "file_name" = "v0.2.yaml"
  #         "file_path" = "cloudformation-products/my-product/v0.2.yaml"
  #       }
  #     }
  #   }
  # }
  cfn_products = {
    for product_name, version_file_names in local.cfn_products_version_file_names :
    product_name => merge(
      {
        versions = {
          for file_name in version_file_names :
          "${regex("(?P<version_name>.+)\\.(?P<file_type>ya?ml|json)", file_name)["version_name"]}" => {
            file_path = join("/", [local.cfn_products_dirname, product_name, file_name])
            file_name = file_name
          }
        }
      },
      try(local.cfn_products_customizations[product_name], {})
    )
  }
}

output "cfn_products" {
  value = local.cfn_products
}

resource "aws_s3_object" "cfn_null_resource" {
  bucket = aws_s3_bucket.product_artifacts.id
  key    = "${local.cfn_products_dirname}/cfn-null-resource.yml"
  source = "${path.module}/cfn-null-resource.yml"
  etag   = filemd5("${path.module}/cfn-null-resource.yml")
}

resource "aws_servicecatalog_product" "cfn_products" {
  for_each            = local.cfn_products
  name                = each.key
  owner               = try(each.value["owner"], aws_servicecatalog_portfolio.portfolio.provider_name)
  description         = try(each.value["description"], null)
  distributor         = try(each.value["distributor"], null)
  support_description = try(each.value["support_description"], null)
  support_email       = try(each.value["support_email"], "sc-product-help@example.com")
  support_url         = try(each.value["support_url"], "https://example.internal/sc-product-help")
  type                = "CLOUD_FORMATION_TEMPLATE"

  # Exactly 1 version must be published using aws_servicecatalog_product. Use a template with no resources. Deactivate
  # or delete this version via ServiceCatalog console after deploying a new product. Additional versions will be
  # published below using "cfn-product-version" module.
  provisioning_artifact_parameters {
    name                        = "Initial-Release-Do-Not-Use"
    description                 = "INITIAL RELEASE - DO NOT USE - PORTFOLIO ADMINISTRATOR SHOULD MANUALLY DELETE THIS VERSION"
    disable_template_validation = true
    type                        = "CLOUD_FORMATION_TEMPLATE"
    template_url                = "https://${aws_s3_bucket.product_artifacts.bucket_regional_domain_name}/${aws_s3_object.cfn_null_resource.key}"
  }
}

resource "aws_servicecatalog_product_portfolio_association" "cfn_products" {
  for_each     = aws_servicecatalog_product.cfn_products
  portfolio_id = aws_servicecatalog_portfolio.portfolio.id
  product_id   = each.value.id
}

# This uses the same launch constraint on all products. Different launch constraint can be applied to
# different products if needed.
resource "aws_servicecatalog_constraint" "cfn_products_launch_constraint" {
  # launch constraint role must be created by cloudformation before launch constraint
  depends_on = [aws_cloudformation_stack_set_instance.svc_ctlg_org, aws_cloudformation_stack.svc_ctlg]

  # aws_servicecatalog_product_portfolio_association must be created before creating constraints
  for_each = aws_servicecatalog_product_portfolio_association.cfn_products

  type         = "LAUNCH"
  description  = "Launch constraint - use role ${local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRoleName} to provision products"
  portfolio_id = each.value.portfolio_id
  product_id   = each.value.product_id

  # https://docs.aws.amazon.com/servicecatalog/latest/dg/API_CreateConstraint.html#servicecatalog-CreateConstraint-request-Parameters
  parameters = jsonencode({
    LocalRoleName = local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRoleName
  })
}

module "cfn_product_version" {
  # {
  #   "my-product:v0.1" = {
  #     "product_name" = "my-product"
  #     "version_name" = "v0.1"
  #     "version" = {
  #       "file_name" = "v0.1.yml"
  #       "file_path" = "cloudformation-products/my-product/v0.1.yml"
  #     }
  #   }
  #   "my-product:v0.2" = {
  #     "product_name" = "my-product"
  #     "version_name" = "v0.2"
  #     "version" = {
  #       "file_name" = "v0.2.yaml"
  #       "file_path" = "cloudformation-products/my-product/v0.2.yaml"
  #     }
  #   }
  # }
  for_each = merge(
    flatten(
      [
        for product_name, product in local.cfn_products :
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

  source           = "./modules/cfn-product-version"
  bucket           = aws_s3_bucket.product_artifacts
  s3_key           = each.value["version"]["file_path"]
  sc_product       = aws_servicecatalog_product.cfn_products[each.value["product_name"]]
  source_file_path = "${path.module}/${each.value["version"]["file_path"]}"
  version_name     = each.value["version_name"]
}
