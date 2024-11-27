locals {
  cfn_svc_ctlg_stack_name = "service-catalog-org-resources"
  cfn_svc_ctlg_parameters = {
    ServiceCatalogUserRolePath       = "/"
    ServiceCatalogUserRoleName       = "ServiceCatalogUser"
    ServiceCatalogLaunchRolePath     = "/"
    ServiceCatalogLaunchRoleName     = "ServiceCatalogLaunchRole"
    ServiceCatalogActionsSsmRolePath = "/"
    ServiceCatalogActionsSsmRoleName = "ServiceCatalogActionsSsmRole"
  }
  cfn_svc_ctlg_template_body = jsonencode({
    Parameters = { for k, v in local.cfn_svc_ctlg_parameters : k => { Type = "String" } }
    Resources = merge(
      {
        # Note - Permission requirements are different for Amazon-owned SSM documents and customer-owned SSM documents.
        # The permissions declared in this role enable executing service actions using either Amazon-owned or
        # customer-owned SSM documents.
        ServiceCatalogUserRole = {
          Type = "AWS::IAM::Role"
          Properties = {
            Path     = { Ref = "ServiceCatalogUserRolePath" }
            RoleName = { Ref = "ServiceCatalogUserRoleName" }
            Tags = [
              {
                Key   = "CfnStackId"
                Value = { Ref = "AWS::StackId" }
              }
            ]
            AssumeRolePolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect = "Allow"
                  Principal = {
                    AWS = [
                      # Trust "Admin" role in management account
                      { "Fn::Sub" = "arn:$${AWS::Partition}:iam::${local.acct_id}:role/Admin" },
                      # Trust "Admin" role in member account
                      { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/Admin" },
                    ]
                  }
                  Action = "sts:AssumeRole"
                },
              ]
            }
            ManagedPolicyArns = [
              { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/ReadOnlyAccess" },
              { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/AWSCloudShellFullAccess" },
            ]
            Policies = [
              {
                PolicyName = "Inline"
                PolicyDocument = {
                  Version = "2012-10-17"
                  Statement = [
                    {
                      Sid      = "ServiceCatalogPassRole"
                      Effect   = "Allow"
                      Action   = "iam:PassRole"
                      Resource = { "Fn::Sub" = "$${ServiceCatalogLaunchRole.Arn}" }
                      Condition = {
                        StringEquals = {
                          "iam:PassedToService" = "servicecatalog.amazonaws.com"
                        }
                      }
                    },
                    {
                      Sid      = "ServiceCatalogServiceActionsPassRole"
                      Effect   = "Allow"
                      Action   = "iam:PassRole"
                      Resource = { "Fn::Sub" = "$${ServiceCatalogActionsSsmRole.Arn}" }
                      Condition = {
                        StringEquals = {
                          "iam:PassedToService" = [
                            # trust servicecatalog for amazon-owned ssm docs
                            "servicecatalog.amazonaws.com",
                            # trust ssm for customer-owned ssm docs
                            "ssm.amazonaws.com",
                          ]
                        }
                      }
                    },
                    {
                      Sid    = "ServiceCatalog"
                      Effect = "Allow"
                      Action = [
                        "servicecatalog:*ProvisionedProductPlan*",
                        "servicecatalog:ExecuteProvisionedProductServiceAction",
                        "servicecatalog:ProvisionProduct",
                        "servicecatalog:TerminateProvisionedProduct",
                        "servicecatalog:UpdateProvisionedProduct",
                        "ssm:StartAutomationExecution", # Required to execute customer-owned ssm docs via service action
                      ]
                      Resource = "*"
                    },
                  ]
                }
              },
            ]
          }
        }

        ServiceCatalogLaunchRole = {
          Type = "AWS::IAM::Role"
          Properties = {
            Path     = { Ref = "ServiceCatalogLaunchRolePath" }
            RoleName = { Ref = "ServiceCatalogLaunchRoleName" }
            AssumeRolePolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect = "Allow"
                  Principal = {
                    Service = "servicecatalog.amazonaws.com"
                  }
                  Action = "sts:AssumeRole"
                  Condition = {
                    StringEquals = {
                      "aws:SourceAccount" = { Ref = "AWS::AccountId" }
                    }
                  }
                },
                {
                  Effect = "Allow"
                  Principal = {
                    # Launch role needs to be assumed by terraform provisioning engine CodeBuild
                    # and ParameterParser Lambda roles
                    AWS = local.acct_id
                  }
                  Action = "sts:AssumeRole"
                },
              ]
            }
            ManagedPolicyArns = [
              { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/AWSCloudFormationFullAccess" },
            ]
            Policies = [
              {
                PolicyName = "Inline"
                PolicyDocument = {
                  Version = "2012-10-17"
                  Statement = [
                    {
                      Sid    = "ProvisionServiceCatalogProducts"
                      Effect = "Allow"
                      Action = [
                        "s3:Get*",
                        "s3:*Bucket*",
                        "s3:*Tag*",
                        "ec2:Describe*",
                        "ec2:RunInstances",
                        "ec2:TerminateInstances",
                        "ec2:*Tags",
                      ]
                      Resource = "*"
                    },
                    # External provisioning engine resource group and tag management
                    # https://docs.aws.amazon.com/servicecatalog/latest/adminguide/getstarted-launchrole-Terraform.html
                    {
                      Sid    = "ServiceCatalogTerraformResourceGroupsAndTags"
                      Effect = "Allow"
                      Action = [
                        "resource-groups:CreateGroup",
                        "resource-groups:ListGroupResources",
                        "resource-groups:DeleteGroup",
                        "resource-groups:Tag",
                        "tag:GetResources",
                        "tag:GetTagKeys",
                        "tag:GetTagValues",
                        "tag:TagResources",
                        "tag:UntagResources",
                      ]
                      Resource = "*"
                    },
                  ]
                }
              },
            ]
          }
        }

        # Note - Permission requirements are different for Amazon-owned SSM documents and customer-owned SSM documents.
        # The permissions declared in this role enable executing service actions using either Amazon-owned or
        # customer-owned SSM documents.
        ServiceCatalogActionsSsmRole = {
          Type = "AWS::IAM::Role"
          Properties = {
            Path     = { Ref = "ServiceCatalogActionsSsmRolePath" }
            RoleName = { Ref = "ServiceCatalogActionsSsmRoleName" }
            AssumeRolePolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect = "Allow"
                  Principal = {
                    Service = [
                      # trust servicecatalog for amazon-owned ssm docs
                      "servicecatalog.amazonaws.com",
                      # trust ssm for customer-owned ssm docs
                      "ssm.amazonaws.com",
                    ]
                  }
                  Action = "sts:AssumeRole"
                  Condition = {
                    StringEquals = {
                      "aws:SourceAccount" = { Ref = "AWS::AccountId" }
                    }
                  }
                },
              ]
            }
            Policies = [
              {
                PolicyName = "Inline"
                PolicyDocument = {
                  Version = "2012-10-17"
                  Statement = [
                    {
                      Sid    = "ExecuteAmazonOwnedSsmDocumentsViaServiceActions"
                      Effect = "Allow"
                      Action = [
                        "ssm:DescribeDocument*",
                        "ssm:GetAutomationExecution",
                        "ssm:StartAutomationExecution",
                      ]
                      Resource = "*"
                    },
                    {
                      Sid    = "ServiceActions"
                      Effect = "Allow"
                      Action = [
                        "s3:DeleteObject",
                        "s3:ListBucket",
                        "ec2:DescribeInstanceStatus",
                        "ec2:StopInstances",
                        "ec2:StartInstances",
                      ]
                      Resource = "*"
                    },
                  ]
                }
              },
            ]
          }
        }

        # Service actions cannot be shared as part of portfolios, they have to be created in each account that receives
        # the portfolio share. CloudFormation stackset that depends_on the provisioning_artifact resources is a good
        # workaround for this.
        # Note - there may be a race condition for new accounts joining the deployment targets where this StackSet
        # attempts to deploy to the new account before the SC portfolio is automatically shared to the account. That
        # could be remediated by disabling auto-deploy for this stackset to slightly delay the deploy of the stack
        # instances in new accounts.
        ServiceActionS3BucketDeleteAllObjects = {
          Type = "AWS::ServiceCatalog::ServiceAction"
          Properties = {
            Name           = "Delete-All-Objects"
            Description    = "Delete all objects from the S3 bucket"
            DefinitionType = "SSM_AUTOMATION"
            Definition = [
              # AssumeRole not declared b/c it is set in the document (see ssm.tf)
              {
                Key   = "Name"
                Value = aws_ssm_document.s3_empty_bucket.arn
              },
              {
                Key   = "Version"
                Value = "$DEFAULT"
              },
              {
                Key   = "Parameters"
                Value = jsonencode([{ Name = "BucketName", Type = "TARGET" }])
              },
            ]
          }
        }

        # Amazon-owned SSM documents fail to execute from the console for me with error:
        #   Error - API returned status 400 with no message.
        # AWS CLI successfully invokes an Amazon-owned SSM document service action:
        #   aws servicecatalog execute-provisioned-product-service-action --service-action-id act-aaaaaaaa --provisioned-product-id pp-bbbbbbbb
        ServiceActionEc2InstanceRestart = {
          Type = "AWS::ServiceCatalog::ServiceAction"
          Properties = {
            Name           = "Restart-EC2-Instance"
            Description    = "Stop then start the EC2 instance"
            DefinitionType = "SSM_AUTOMATION"
            Definition = [
              # AssumeRole not declared b/c it is set in the document (see ssm.tf)
              {
                Key   = "Name"
                Value = aws_ssm_document.ec2_restart_instance.arn
              },
              {
                Key   = "Version"
                Value = "$DEFAULT"
              },
              {
                Key   = "Parameters"
                Value = jsonencode([{ Name = "InstanceId", Type = "TARGET" }])
              },
            ]
          }
        }
        # Since Amazon-owned SSM documents service actions don't seem to work from the console, recreate customer-owned
        # documents with the same functionality. Customer-owned SSM document service actions execute from the console
        # no problem.
        ServiceActionAwsRestartEC2Instance = {
          Type = "AWS::ServiceCatalog::ServiceAction"
          Properties = {
            Name           = "AWS-RestartEC2Instance"
            Description    = "Stop then start the EC2 instance"
            DefinitionType = "SSM_AUTOMATION"
            Definition = [
              {
                Key   = "Name"
                Value = "AWS-RestartEC2Instance"
              },
              {
                Key   = "Version"
                Value = "$DEFAULT"
              },
              {
                Key = "Parameters"
                Value = jsonencode([
                  { Name = "InstanceId", Type = "TARGET" },
                  { Name = "AutomationAssumeRole", Type = "TEXT_VALUE" },
                ])
              },
              {
                Key   = "AssumeRole"
                Value = { "Fn::Sub" = "$${ServiceCatalogActionsSsmRole.Arn}" }
              },
            ]
          }
        }
      },
      # Generate ServiceActionAssociation resources to associate each service action with every version of the
      # appropriate product.
      # TODO: Logic using a local to make this less complex and easier to read
      {
        for provisioning_artifact in [for cpv in module.cfn_product_version : cpv.provisioning_artifact] :
        "SvcActS3BucketDeleteAllObjects${replace(provisioning_artifact.provisioning_artifact_id, "/[\\.-]/", "")}" => {
          Type = "AWS::ServiceCatalog::ServiceActionAssociation"
          Properties = {
            ProductId              = aws_servicecatalog_product.cfn_products["s3-bucket"].id
            ProvisioningArtifactId = provisioning_artifact.provisioning_artifact_id
            ServiceActionId        = { "Ref" = "ServiceActionS3BucketDeleteAllObjects" }
          }
        }
        if provisioning_artifact.product_id == aws_servicecatalog_product.cfn_products["s3-bucket"].id
      },
      {
        for provisioning_artifact in [for cpv in module.cfn_product_version : cpv.provisioning_artifact] :
        "SvcActEc2InstanceRestart${replace(provisioning_artifact.provisioning_artifact_id, "/[\\.-]/", "")}" => {
          Type = "AWS::ServiceCatalog::ServiceActionAssociation"
          Properties = {
            ProductId              = aws_servicecatalog_product.cfn_products["ec2-instance"].id
            ProvisioningArtifactId = provisioning_artifact.provisioning_artifact_id
            ServiceActionId        = { "Ref" = "ServiceActionEc2InstanceRestart" }
          }
        }
        if provisioning_artifact.product_id == aws_servicecatalog_product.cfn_products["ec2-instance"].id
      },
      {
        for provisioning_artifact in [for cpv in module.cfn_product_version : cpv.provisioning_artifact] :
        "SvcActAwsRestartEC2Instance${replace(provisioning_artifact.provisioning_artifact_id, "/[\\.-]/", "")}" => {
          Type = "AWS::ServiceCatalog::ServiceActionAssociation"
          Properties = {
            ProductId              = aws_servicecatalog_product.cfn_products["ec2-instance"].id
            ProvisioningArtifactId = provisioning_artifact.provisioning_artifact_id
            ServiceActionId        = { "Ref" = "ServiceActionAwsRestartEC2Instance" }
          }
        }
        if provisioning_artifact.product_id == aws_servicecatalog_product.cfn_products["ec2-instance"].id
      },
    )
  })
}

resource "aws_cloudformation_stack_set" "svc_ctlg" {
  name             = local.cfn_svc_ctlg_stack_name
  description      = "Resources deployed to all accounts to use Service Catalog portfolio"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  permission_model = "SERVICE_MANAGED"
  auto_deployment {
    enabled = true
  }

  lifecycle {
    ignore_changes = [
      administration_role_arn, # Using SERVICE_MANAGED permissions, this does not need to be defined
    ]
  }

  parameters    = local.cfn_svc_ctlg_parameters
  template_body = local.cfn_svc_ctlg_template_body
}

resource "aws_cloudformation_stack_set_instance" "svc_ctlg_org" {
  stack_set_name = aws_cloudformation_stack_set.svc_ctlg.name
  deployment_targets {
    organizational_unit_ids = [local.org.roots[0].id]
  }
}

# These resources must also be deployed to the mgmt account
resource "aws_cloudformation_stack" "svc_ctlg" {
  name          = local.cfn_svc_ctlg_stack_name
  capabilities  = ["CAPABILITY_NAMED_IAM"]
  parameters    = local.cfn_svc_ctlg_parameters
  template_body = local.cfn_svc_ctlg_template_body
}
