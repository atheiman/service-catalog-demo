locals {
  lambda_runtime = "python3.11"
}

resource "aws_iam_role" "lambda" {
  name_prefix = "Lambda-TerraformSvcCtlgEngine-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.acct_id
          }
        }
      },
    ]
  })

  managed_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
  ]
}

resource "aws_iam_role_policy" "lambda" {
  name_prefix = "Terraform-"
  role        = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "servicecatalog:NotifyProvisionProductEngineWorkflowResult",
          "servicecatalog:NotifyTerminateProvisionedProductEngineWorkflowResult",
          "servicecatalog:NotifyUpdateProvisionedProductEngineWorkflowResult",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:${local.partition}:iam::*:role${var.svc_ctlg_launch_role_path}${var.svc_ctlg_launch_role_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
        ]
        Resource = [for q in aws_sqs_queue.product_operation : q.arn]
      },
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.product_operation.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
      },
    ]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"

  # # read content of each file from lambda code dir and ensure consistent line endings across linux and windows
  # dynamic "source" {
  #   for_each = fileset("${path.module}/lambda", "**")
  #   content {
  #     filename = source.value
  #     content  = replace(file("${path.module}/lambda/${source.value}"), "\r\n", "\n")
  #   }
  # }
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = toset([
    aws_lambda_function.parameter_parser.function_name,
    aws_lambda_function.start_product_operation.function_name,
    aws_lambda_function.succeeded_product_operation.function_name,
    aws_lambda_function.failed_product_operation.function_name,
  ])
  name              = "/aws/lambda/${each.key}"
  retention_in_days = 14
}

# https://docs.aws.amazon.com/servicecatalog/latest/adminguide/external-engine.html#external-engine-parameters
resource "aws_lambda_function" "parameter_parser" {
  function_name    = "ServiceCatalogExternalParameterParser"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "parameter_parser.handler"
  runtime          = local.lambda_runtime
  timeout          = 10

  environment {
    variables = {
      VARIABLES_TF_JSON_FILENAME = "variables.tf.json"
    }
  }
}

resource "aws_lambda_permission" "parameter_parser_servicecatalog" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parameter_parser.function_name
  principal     = "servicecatalog.amazonaws.com"
}

# https://docs.aws.amazon.com/servicecatalog/latest/adminguide/external-engine.html#external-engine-provisioning
resource "aws_lambda_function" "start_product_operation" {
  function_name    = "TerraformSvcCtlgEngineStartProductOperation"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "start_product_operation.handler"
  runtime          = local.lambda_runtime
  timeout          = 10

  environment {
    variables = {
      STATE_MACHINE_ARN   = aws_sfn_state_machine.product_operation.arn
      TFSTATE_BUCKET_NAME = aws_s3_bucket.tfstate.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "start_product_operation_sqs_queues" {
  for_each = aws_sqs_queue.product_operation

  event_source_arn = each.value.arn
  function_name    = aws_lambda_function.start_product_operation.function_name
  batch_size       = 1
}

resource "aws_lambda_function" "succeeded_product_operation" {
  function_name    = "TerraformSvcCtlgEngineSucceededProductOperation"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "succeeded_product_operation.handler"
  runtime          = local.lambda_runtime
  timeout          = 10
}

resource "aws_lambda_function" "failed_product_operation" {
  function_name    = "TerraformSvcCtlgEngineFailedProductOperation"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "failed_product_operation.handler"
  runtime          = local.lambda_runtime
  timeout          = 10
}
