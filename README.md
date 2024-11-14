# Service Catalog Demo

This terraform project provisions a Service Catalog portfolio and products into an organization management account. The portfolio is shared to every account in the organization.

Additional product versions can be added to [`cloudformation-products/`](./cloudformation-products) and they will automatically be deployed as part of the portfolio.

This demo is not meant to be deployed as is to any organization, at least a few changes would need to be made to safely drop this into an organization for testing:

- `cloudformation.tf` `aws_cloudformation_stack_set` resource should target an OU id for testing rather than targeting the entire organization.
- `service_catalog.tf` shows how to share the portfolio to the entire organization (the Terraform resource has bugs). This should likely be updated to target an OU id for testing rather than targeting the entire organization.
- `cloudformation.tf` CloudFormation template body contains an `AWS::IAM::Role` resource `ServiceCatalogUserRole` which can be assumed by the IAM role `Admin` in the management account, and `Admin` in the role's account. This should likely be removed or at least the trust policy should be updated.
- `service_catalog.tf` `aws_servicecatalog_principal_portfolio_association` resource should be updated based on changes to CloudFormation resource `ServiceCatalogUserRole` above.
- probably other considerations ...

Components of this demo:

- portfolio sharing
- portfolio access
- portfolio tag options
- two simple products: `s3-bucket` and `ec2-instance` (_very_ simplified)
- service actions using Amazon-owned and customer-owned SSM automation documents ("runbooks")
- Terraform logic to automatically deploy new products and product versions by simply adding files to [`cloudformation-products/`](./cloudformation-products)
- product launch constraints
