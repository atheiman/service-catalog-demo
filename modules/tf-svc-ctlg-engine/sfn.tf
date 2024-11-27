resource "aws_iam_role" "sfn" {
  name_prefix = "StepFunctions-TerraformSvcCtlgEngine-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.acct_id
          }
        }
      },
    ]
  })

  managed_policy_arns = []
}

resource "aws_iam_role_policy" "sfn" {
  name_prefix = "Terraform-"
  role        = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # https://docs.aws.amazon.com/step-functions/latest/dg/connect-codebuild.html#codebuild-iam
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild",
        ]
        Resource = aws_codebuild_project.terraform.arn
      },
      {
        Effect = "Allow"
        Action = [
          "events:DescribeRule",
          "events:PutRule",
          "events:PutTargets",
        ]
        # eventbridge rule managed by sfn + codebuild integration
        Resource = "arn:${local.partition}:events:${local.region}:${local.acct_id}:rule/StepFunctionsGetEventForCodeBuildStartBuildRule"
      },
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.failed_product_operation.arn,
          aws_lambda_function.succeeded_product_operation.arn,
        ]
      },
    ]
  })
}

resource "aws_sfn_state_machine" "product_operation" {
  name     = "TerraformSvcCtlgEngineProductOperation"
  role_arn = aws_iam_role.sfn.arn

  # start codebuild sync wait
  # invoke lambda succeeded_product_operation
  # any failure at any time invoke lambda failed_product_operation

  definition = jsonencode({
    StartAt = "StartCodeBuildTerraformOperation"
    States = {
      StartCodeBuildTerraformOperation = {
        Type     = "Task"
        Comment  = "Run CodeBuild terraform operation and wait for completion"
        Resource = "arn:${local.partition}:states:::codebuild:startBuild.sync"
        Parameters = {
          ProjectName                      = aws_codebuild_project.terraform.name
          "EnvironmentVariablesOverride.$" = "$.codebuild.environmentVariablesOverride"
        }
        # Retry terraform failures by rerunning codebuild
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            MaxAttempts     = 1
            IntervalSeconds = 10
          }
        ]
        # TODO: get this OutputPath working to not pass messy API resp data into future states
        # OutputPath = "$.Build"
        ResultPath = "$.codebuild.build"
        Next       = "LambdaSucceededProductOperation"
        Catch = [
          {
            ErrorEquals = ["States.TaskFailed"]
            Next        = "LambdaFailedProductOperation"
            ResultPath  = "$.Error"
          },
        ]
      }

      LambdaSucceededProductOperation = {
        Type     = "Task"
        Comment  = "Notify ServiceCatalog of successful product operation"
        Resource = "arn:${local.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.succeeded_product_operation.arn
          "Payload.$"  = "$"
        }
        Next = "Succeed"
      }

      Succeed = {
        Type = "Succeed"
        # Comment = "No errors encountered"
      }

      LambdaFailedProductOperation = {
        Type     = "Task"
        Comment  = "Notify ServiceCatalog of error encountered during product operation"
        Resource = "arn:${local.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.failed_product_operation.arn
          "Payload" = {
            "State.$"   = "$"
            "Context.$" = "$$"
          }
        }
        Next = "Fail"
      }

      Fail = {
        Type = "Fail"
        # Error = "CustomErrorType"
        # Cause = "more info"
      }
    }
  })
}
