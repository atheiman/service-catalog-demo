module "tf-svc-ctlg-engine" {
  source                    = "./modules/tf-svc-ctlg-engine"
  svc_ctlg_launch_role_path = local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRolePath
  svc_ctlg_launch_role_name = local.cfn_svc_ctlg_parameters.ServiceCatalogLaunchRoleName
}

resource "aws_servicecatalog_organizations_access" "svc_ctlg_orgs_access" {
  enabled = "true"
}

resource "aws_servicecatalog_portfolio" "portfolio" {
  name          = "Example Portfolio"
  description   = "Demo portfolio for service catalog products"
  provider_name = "Example Organization"
}

# GovCloud org shares must be done manually:
#   https://github.com/hashicorp/terraform-provider-aws/issues/39861
# Org sharing is also not yet supported in CloudFormation:
#   https://github.com/aws-cloudformation/cloudformation-coverage-roadmap/issues/594
# Share via AWS CLI:
#   aws servicecatalog create-portfolio-share \
#     --portfolio-id port-aaaaaaaaaaaaa \
#     --organization-node "Type=ORGANIZATION,Value=o-bbbbbbbbbb" \
#     --share-tag-options \
#     --share-principals
# resource "aws_servicecatalog_portfolio_share" "org" {
#  portfolio_id      = aws_servicecatalog_portfolio.portfolio.id
#  principal_id      = local.org.arn
#  type              = "ORGANIZATION" # ORGANIZATION | ORGANIZATIONAL_UNIT | ORGANIZATION_MEMBER_ACCOUNT
#  share_tag_options = true
# }

resource "aws_servicecatalog_principal_portfolio_association" "svc_ctlg_user" {
  principal_type = "IAM_PATTERN"
  portfolio_id   = aws_servicecatalog_portfolio.portfolio.id
  principal_arn  = "arn:${local.partition}:iam:::role${local.cfn_svc_ctlg_parameters.ServiceCatalogUserRolePath}${local.cfn_svc_ctlg_parameters.ServiceCatalogUserRoleName}"
  # Example to allow access to any role (in accounts the portfolio has been shared with):
  #principal_arn  = "arn:${local.partition}:iam:::role/*"
}

resource "aws_servicecatalog_tag_option" "portfolio_tag_options" {
  for_each = toset(
    flatten([
      for k, values in {
        finops_project_number = ["1111", "2222"]
        finops_project_name   = ["project-a", "project-b"]
      } :
      [for v in values : "${k}::${v}"]
    ])
  )

  key   = split("::", each.key)[0]
  value = split("::", each.key)[1]
}

resource "aws_servicecatalog_tag_option_resource_association" "portfolio_tag_options" {
  for_each      = aws_servicecatalog_tag_option.portfolio_tag_options
  resource_id   = aws_servicecatalog_portfolio.portfolio.id
  tag_option_id = each.value.id
}

resource "aws_s3_bucket" "product_artifacts" {
  bucket_prefix = "svc-ctlg-artifacts-"
}
