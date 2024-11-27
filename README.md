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
- two simple CloudFormation template products: `s3-bucket` and `ec2-instance`
- service actions for CloudFormation products using Amazon-owned and customer-owned SSM automation documents ("runbooks")
- Terraform external provisioning engine (described below)
- automatically deploy new products and product versions by simply adding files to [`cloudformation-products/`](./cloudformation-products) or [`terraform-products/`](./terraform-products)
- product launch constraints (required tags and required launch role)
- minimal IAM role `ServiceCatalogUserRole` deployed to management and workload accounts to demonstrate launching products using a role with restricted permissions

## Terraform External Provisioning

[`modules/tf-svc-ctlg-engine`](modules/tf-svc-ctlg-engine) contains a Service Catalog external engine for Terraform product provisioning. The engine architecture is based off of [github.com/aws-ia/terraform-aws-sce-tf-community](https://github.com/aws-ia/terraform-aws-sce-tf-community). External engines must conform to the API interface documented in [External Engines for AWS Service Catalog](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/external-engine.html). Only one external engine may be deployed per region per account, so if you already have resources for an external engine deployed this module will fail. Below is a summary of the external engine workflow:

1. External products are published to end users using the same workflow as CloudFormation products. Terraform products are published to S3 as `.zip` packages. They must contain `variables.tf.json` to define all variables the user should input during provisioning. `variables.tf.json` uses the [Terraform JSON configuration syntax](https://developer.hashicorp.com/terraform/language/syntax/json).
1. Service Catalog stores the published product artifact again in an AWS-managed bucket outside of the portfolio account.
1. When a user begins provisioning a product version (`DescribeProvisioningParameters` API), Service Catalog invokes [Lambda function `ServiceCatalogExternalParameterParser`](modules/tf-svc-ctlg-engine/lambda/parameter_parser.py) in the portfolio account with the location of the artifact in S3 (which must be downloaded using the product launch role). The Lambda function returns input parameters for the user to input in the Service Catalog console.
1. When the user submits the `ProvisionProduct` API request, Service Catalog publishes a product operation request message to [SQS queue `ServiceCatalogExternalProvisionOperationQueue`](modules/tf-svc-ctlg-engine/sqs.tf) in the portfolio account.
1. [Lambda function `TerraformSvcCtlgEngineStartProductOperation`](modules/tf-svc-ctlg-engine/lambda/start_product_operation.py) in the portfolio account is [invoked by an SQS event source mapping Lambda with the message](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html). This function builds environment variables for customizing the CodeBuild execution of Terraform (described below). Then the function starts [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) with input containing the CodeBuild environment variables. If the function fails, it calls the [`NotifyProvisionProductEngineWorkflowResult`](https://docs.aws.amazon.com/servicecatalog/latest/dg/API_NotifyProvisionProductEngineWorkflowResult.html) API to notify Service Catalog of the failure.
1. [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) starts [CodeBuild project `TerraformSvcCtlgEngine`](modules/tf-svc-ctlg-engine/codebuild.tf) with environment variables to customize Terraform execution. Terraform uses [the S3 backend for remote state storage](https://developer.hashicorp.com/terraform/language/backend/s3#state-storage). [Terraform output values](https://developer.hashicorp.com/terraform/language/values/outputs) are stored in the same S3 bucket as the Terraform state file. If any `terraform` CLI commands fail in the CodeBuild build, stderr is captured and published to the same S3 bucket.
1. If [the CodeBuild project `TerraformSvcCtlgEngine`](modules/tf-svc-ctlg-engine/codebuild.tf) succeeds, [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) then calls [Lambda function `TerraformSvcCtlgEngineSucceededProductOperation`](modules/tf-svc-ctlg-engine/lambda/succeeded_product_operation.py). The Lambda function downloads Terraform output values from S3, and calls the [`NotifyProvisionProductEngineWorkflowResult`](https://docs.aws.amazon.com/servicecatalog/latest/dg/API_NotifyProvisionProductEngineWorkflowResult.html) API to notify Service Catalog of the successful provisioning operation, and includes Terraform output values to be displayed to the end user. Finally, [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) succeeds.
1. If [the CodeBuild project `TerraformSvcCtlgEngine`](modules/tf-svc-ctlg-engine/codebuild.tf) fails, [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) then invokes [Lambda function `TerraformSvcCtlgEngineFailedProductOperation`](modules/tf-svc-ctlg-engine/lambda/failed_product_operation.py). The Lambda function downloads Terraform stderr from S3, and calls the [`NotifyProvisionProductEngineWorkflowResult`](https://docs.aws.amazon.com/servicecatalog/latest/dg/API_NotifyProvisionProductEngineWorkflowResult.html) API to notify Service Catalog of the failed provisioning operation, and includes Terraform stderr to be displayed to the end user. _Note - as of Nov 2024, failed `PROVISION_PRODUCT` operations do not display the provided failure reason to the end user, only `Internal failure.` is displayed_. Finally, [Step Functions State Machine `TerraformSvcCtlgEngineProductOperation`](modules/tf-svc-ctlg-engine/sfn.tf) fails.

### TODO
- Dead -letter SQS queue `ServiceCatalogExternal-DeadLetter` message handling - call `NotifyProvisionProductEngineWorkflowResult` API with basic failure message. This would remove `try` / `catch` logic in `start_product_operation.py`
