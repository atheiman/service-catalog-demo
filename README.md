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
- Terraform external provisioning engine and example products (described below)

## Terraform External Provisioning

[`modules/tf-svc-ctlg-engine`](modules/tf-svc-ctlg-engine) contains a Service Catalog external engine for Terraform product provisioning. The engine architecture is based off of [github.com/aws-ia/terraform-aws-sce-tf-community](https://github.com/aws-ia/terraform-aws-sce-tf-community). External engines must conform to the API interface documented in [External Engines for AWS Service Catalog](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/external-engine.html). Only one external engine may be deployed per region per account, so if you already have resources for an external engine deployed this module will fail. Below is a summary of the external engine workflow:

1. External products are published to end users. Terraform products are published to S3 as `.zip` packages. They must contain `variables.tf.json` to define all variables the user should input during provisioning. `variables.tf.json` uses the [Terraform JSON configuration syntax](https://developer.hashicorp.com/terraform/language/syntax/json).
1. Service Catalog stores the published product artifact again in an AWS-managed bucket outside of the portfolio account.
1. When a user begins provisioning a product version, Service Catalog invokes [Lambda function `ServiceCatalogExternalParameterParser`](modules/tf-svc-ctlg-engine/lambda/parameter_parser.py) in the portfolio account with the location of the artifact in S3 (which must be downloaded using the product launch role). The Lambda function returns input parameters for the user to input in the Service Catalog console.
1. When the user submits the ProvisionProduct request, Service Catalog publishes a message to [SQS queue `ServiceCatalogExternalProvisionOperationQueue`](modules/tf-svc-ctlg-engine/sqs.tf) in the portfolio account.
1. [Lambda function `TerraformSvcCtlgEngineStartProductOperation`](modules/tf-svc-ctlg-engine/lambda/start_product_operation.py) in the portfolio account is [invoked by an SQS event source mapping Lambda](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html) with the message.
