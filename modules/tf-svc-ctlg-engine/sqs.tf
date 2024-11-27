resource "aws_sqs_queue" "product_operation_deadletter" {
  name                      = "ServiceCatalogExternal-DeadLetter"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # max retention to investigate failures
}

resource "aws_sqs_queue" "product_operation" {
  for_each = toset([
    "ServiceCatalogExternalProvisionOperationQueue",
    "ServiceCatalogExternalUpdateOperationQueue",
    "ServiceCatalogExternalTerminateOperationQueue",
  ])

  name                       = each.key
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.product_operation_deadletter.arn
    maxReceiveCount     = 1 # `receive count = 5` allows 4 retries before sending message to deadletter queue
  })
}

resource "aws_sqs_queue_policy" "product_operation" {
  for_each = aws_sqs_queue.product_operation

  queue_url = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "servicecatalog.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = "*"
      }
    ]
  })
}
