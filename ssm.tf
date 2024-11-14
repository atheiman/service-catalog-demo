resource "aws_ssm_document" "s3_empty_bucket" {
  name            = "s3-empty-bucket"
  document_format = "YAML"
  document_type   = "Automation"
  target_type     = "/AWS::S3::Bucket"

  # Sharing docs only works direct to account ids, and this terraform approach maybe only supports up to 20 accounts.
  # An alternative approach would be deploy the doc to each account (cfn stackset) rather than sharing. Or custom
  # method to share the doc to all accounts in the org (aws cli loop through all account ids).
  permissions = {
    type        = "Share"
    account_ids = join(",", sort([for acct in local.org.accounts : acct.id]))
  }

  content = <<-DOC
    schemaVersion: '0.3'
    description: Delete all objects from an S3 bucket
    assumeRole: "{{ AutomationAssumeRole }}"
    parameters:
      BucketName:
        type: String
        description: "(Required) S3 Bucket to be emptied"
      AutomationAssumeRole:
        type: String
        description: >-
          IAM role ARN to pass to automation execution. Role "${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRoleName}" will be selected by default.
        default: >-
          arn:{{global:AWS_PARTITION}}:iam::{{global:ACCOUNT_ID}}:role${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRolePath}${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRoleName}
    mainSteps:
      - name: EmptyBucket
        action: 'aws:executeScript'
        inputs:
          Runtime: python3.11
          Handler: handler
          InputPayload:
            BucketName: '{{BucketName}}'
          Script: |
            import boto3
            sts = boto3.client("sts")
            s3 = boto3.resource("s3")

            def handler(event, context):
              print("Deleting objects as principal:", sts.get_caller_identity()["Arn"])
              s3.Bucket(event["BucketName"]).objects.delete()
  DOC
}

resource "aws_ssm_document" "ec2_restart_instance" {
  name            = "ec2-restart-instance"
  document_format = "YAML"
  document_type   = "Automation"
  target_type     = "/AWS::EC2::Instance"

  # Sharing docs only works direct to account ids, and this terraform approach maybe only supports up to 20 accounts.
  # An alternative approach would be deploy the doc to each account (cfn stackset) rather than sharing. Or custom
  # method to share the doc to all accounts in the org (aws cli loop through all account ids).
  permissions = {
    type        = "Share"
    account_ids = join(",", sort([for acct in local.org.accounts : acct.id]))
  }

  content = <<-DOC
    description: Stop then start EC2 instance
    schemaVersion: '0.3'
    assumeRole: "{{ AutomationAssumeRole }}"
    parameters:
      InstanceId:
        type: String
        description: (Required) EC2 Instance to stop then start
      AutomationAssumeRole:
        type: String
        description: >-
          IAM role ARN to pass to automation execution. Role "${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRoleName}" will be selected by default.
        default: >-
          arn:{{global:AWS_PARTITION}}:iam::{{global:ACCOUNT_ID}}:role${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRolePath}${local.cfn_svc_ctlg_parameters.ServiceCatalogActionsSsmRoleName}
    mainSteps:
      - name: stopInstances
        action: 'aws:changeInstanceState'
        inputs:
          InstanceIds: '{{ InstanceId }}'
          DesiredState: stopped
      - name: startInstances
        action: 'aws:changeInstanceState'
        inputs:
          InstanceIds: '{{ InstanceId }}'
          DesiredState: running
  DOC
}
