# Handle external engine operations PROVISION_PRODUCT, UPDATE_PROVISIONED_PRODUCT, and TERMINATE_PROVISIONED_PRODUCT. These
# events are read from sqs queue and start step function state machines for each of these events.

import json
import boto3
import os

sfn = boto3.client("stepfunctions")
sc = boto3.client("servicecatalog")

# Event example from SQS queue event source mapping
# {
#     "Records": [
#         {
#             "messageId": "f828161a-aceb-4b26-bccf-c5e5106a0d1d",
#             "receiptHandle": "AQEBgiYJloJw91gpAjf+4bOFK88ftoLRu/wvB+yewi3SSrpIcuGHLGfF99YN9wq03USKJzhCmX4MKx0iarGjnMPwIXuT6cOjb01PYzzTRC/WVioGozupfYPzlqXLrxswc1R2VWSXJPTGossWuPIX2x08QQNO+QJ4BhJuXGQwz1HRFNZszP2srZIJRqvAUpo9lrWOsjAc0VrQ9Pklboja9TIpNWbNYmbzo/yvYpnGr8QWjoQWX8BzYHomWoJvpOKt8dwKXYgoUntcd4dqjh0G/FcRLc0z/AJQYolONUGnWs7/yszk3n3FQOzgFR9ZtcysYcckIWOQTkOdp96QD77/xjrmNt257Vy3+Gz0xL+R8o6CQOjGNibScJNi6Qgnh8a/w5Cf/XfnDhdjj7jYGPvbRHRqQmyRd6pXfHD57G9q2mmEVio7GbsreueGNvKjTbP+vCxG",
#             "body": "{\"token\":\"965d4597-3088-41ae-87dc-3498daf1d69d\",\"operation\":\"PROVISION_PRODUCT\",\"provisionedProductId\":\"pp-ctfiwih3iodci\",\"provisionedProductName\":\"tf-s3-bucket-11261452\",\"productId\":\"prod-xayh7l3a7e66m\",\"provisioningArtifactId\":\"pa-qhjerwxbaulto\",\"recordId\":\"rec-rf5pmkrnabmx4\",\"launchRoleArn\":\"arn:aws:iam::111111111111:role/ServiceCatalogLaunchRole\",\"artifact\":{\"path\":\"S3://sc-1f4e39d8d6ee2486532d12570660174a-us-gov-west-1/out/7a4b8a59bd08f838400ad80309444392/60413ed8e0ba1e67a89ecd3b1f2280e9-466c76bf1ec0618e4672d8061734b1c2473207d1d225e2cde200bece3f37ef50-bb6b1286bd6031a333ce4ecd6285008449134e044ee16407f8090cc7c5db13d9-1732629850224-f9596553-597b-4626-80c9-bcd71d092c98\",\"type\":\"AWS_S3\"},\"identity\":{\"principal\":\"AROASGNG33TL2BDDOJDZK\",\"awsAccountId\":\"111111111111\",\"organizationId\":null},\"parameters\":[{\"key\":\"bucket_name_prefix\",\"value\":\"the-prefix-\"}],\"tags\":[{\"key\":\"finops_project_name\",\"value\":\"project-a\"},{\"key\":\"finops_project_number\",\"value\":\"2222\"}]}",
#             "attributes": {
#                 "ApproximateReceiveCount": "1",
#                 "AWSTraceHeader": "Root=1-6745d55b-497a0aae156bb7084a3c7a5c;Parent=62ff1495bb8d8406;Sampled=0",
#                 "SentTimestamp": "1732629851914",
#                 "SenderId": "AROAUVTKV5AU27VS32ZCQ:KovuGenericWorkflow",
#                 "ApproximateFirstReceiveTimestamp": "1732629851917"
#             },
#             "messageAttributes": {},
#             "md5OfBody": "83678d08faa3cdbd647b670fd185ddbf",
#             "eventSource": "aws:sqs",
#             "eventSourceARN": "arn:aws:sqs:us-gov-west-1:222222222222:ServiceCatalogExternalProvisionOperationQueue",
#             "awsRegion": "us-gov-west-1"
#         }
#     ]
# }

# PROVISION_PRODUCT example (UPDATE_PROVISIONED_PRODUCT is same)
# {
#     "token": "b3f9a7f7-a162-4fa5-b092-302c9afc0153",
#     "operation": "PROVISION_PRODUCT",
#     "provisionedProductId": "pp-wp3ziihdnvmse",
#     "provisionedProductName": "tf-s3-bucket-11261418",
#     "productId": "prod-xayh7l3a7e66m",
#     "provisioningArtifactId": "pa-qhjerwxbaulto",
#     "recordId": "rec-6zfcyj6jqsoj6",
#     "launchRoleArn": "arn:aws:iam::111111111111:role/ServiceCatalogLaunchRole",
#     "artifact": {
#         "path": "S3://sc-1f4e39d8d6ee2486532d12570660174a-us-gov-west-1/out/7a4b8a59bd08f838400ad80309444392/60413ed8e0ba1e67a89ecd3b1f2280e9-466c76bf1ec0618e4672d8061734b1c2473207d1d225e2cde200bece3f37ef50-bb6b1286bd6031a333ce4ecd6285008449134e044ee16407f8090cc7c5db13d9-1732630890914-d983744d-affd-4803-85e3-976c018951fe",
#         "type": "AWS_S3"
#     },
#     "identity": {
#         "principal": "AROASGNG33TL2BDDOJDZK",
#         "awsAccountId": "111111111111",
#         "organizationId": null
#     },
#     "parameters": [
#         {
#             "key": "bucket_name_prefix",
#             "value": "asdfg"
#         }
#     ],
#     "tags": [
#         {
#             "key": "finops_project_name",
#             "value": "project-a"
#         },
#         {
#             "key": "finops_project_number",
#             "value": "2222"
#         }
#     ]
# }
# TERMINATE_PROVISIONED_PRODUCT example
# {
#   "token": "8b905837-1775-4ddb-9128-e25c6623bee6",
#   "operation": "TERMINATE_PROVISIONED_PRODUCT",
#   "provisionedProductId": "pp-khg32b4f465ps",
#   "provisionedProductName": "tf-s3-bucket-11252127",
#   "recordId": "rec-kojanzxest74o",
#   "launchRoleArn": "arn:aws:iam::111111111111:role/ServiceCatalogLaunchRole",
#   "identity": {
#     "principal": "AROASGNG33TL2BDDOJDZK",
#     "awsAccountId": "111111111111",
#     "organizationId": null
#   }
# }


def handler(event, context):
    print("lambda invocation event payload:")
    print(json.dumps(event, default=str))

    # Lambda will be invoked with 1 or more messages from the SQS queues. If function fails, the message is released
    # back into the queue for reprocessing. After "maxReceiveCount" attempts the message will be sent to dead letter
    # queue.
    for record in event["Records"]:
        op_req = json.loads(record["body"])
        print("sqs message operation request received:")
        print(json.dumps(op_req, default=str))

        try:
            handle_op_req(op_req)
        except Exception as e:
            notify_args = {
                "WorkflowToken": op_req["token"],
                "RecordId": op_req["recordId"],
                "Status": "FAILED",
                "FailureReason": (
                    f"Error encountered in Lambda function {context.invoked_function_arn} starting"
                    f" Terraform provisioning: {repr(e)}"
                ),
            }
            operation = op_req["operation"]

            print(f"Notifying servicecatalog of product operation result for operation '{operation}' with args:")
            print(json.dumps(notify_args, default=str))

            if operation == "PROVISION_PRODUCT":
                sc.notify_provision_product_engine_workflow_result(**notify_args)
            elif operation == "UPDATE_PROVISIONED_PRODUCT":
                sc.notify_update_provisioned_product_engine_workflow_result(**notify_args)
            elif operation == "TERMINATE_PROVISIONED_PRODUCT":
                sc.notify_terminate_provisioned_product_engine_workflow_result(**notify_args)

            raise e


def handle_op_req(op_req):
    # Build codebuild env vars for terraform execution (state machine will pass this to codebuild). This is much easier
    # to build in this lambda function before running state machine rather than in state machine language.
    s3_prefix = f"{op_req['identity']['awsAccountId']}/{op_req['provisionedProductId']}"
    codebuild_env_vars = [
        {
            "Name": "LAUNCH_ROLE_ARN",
            "Value": op_req["launchRoleArn"],
        },
        {
            "Name": "OPERATION",
            "Value": op_req["operation"],
        },
        {
            "Name": "OUTPUTS_S3_URI",
            "Value": f"s3://{os.environ['TFSTATE_BUCKET_NAME']}/{s3_prefix}.tfoutputs.json",
        },
        {
            "Name": "STDERR_S3_URI",
            "Value": f"s3://{os.environ['TFSTATE_BUCKET_NAME']}/{s3_prefix}-{op_req['recordId']}.stderr.txt",
        },
        {  # Provide codebuild job with terraform s3 backend config in .tf.json format
            "Name": "S3_BACKEND_JSON",
            "Value": json.dumps(
                {
                    "terraform": {
                        "backend": {
                            "s3": {
                                "bucket": os.environ["TFSTATE_BUCKET_NAME"],
                                "key": f"{s3_prefix}.tfstate",
                                # Use the codebuild execution role (default profile) to read/write state file in s3
                                # bucket. Other terraform resource provisioning api calls use launch-role profile.
                                "profile": "default",
                            }
                        }
                    }
                }
            ),
        },
    ]

    # Set env var for terraform artifact s3 location
    if "artifact" in op_req and op_req["artifact"]["type"] == "AWS_S3":
        codebuild_env_vars.append(
            {
                "Name": "ARTIFACT_S3_URI",
                # artifact.path prefix S3:// (uppercase) is an invalid s3 uri, replace prefix with s3:// (lowercase)
                "Value": "s3://" + op_req["artifact"]["path"][5:],
            }
        )
    elif op_req["operation"] != "TERMINATE_PROVISIONED_PRODUCT":
        # Only terminate operation should be missing an artifact s3 uri
        raise Exception("Could not load artifact S3 uri from product operation request")

    # Set env var for terraform default_tags from sc product tags
    if "tags" in op_req:
        codebuild_env_vars.append(
            {
                "Name": f"TF_VAR_default_tags_json",
                "Value": json.dumps({t["key"]: t["value"] for t in op_req["tags"]}, default=str),
            }
        )

    # Set env vars for terraform variables from sc product parameters
    for param in op_req.get("parameters", []):
        codebuild_env_vars.append(
            {
                "Name": f"TF_VAR_{param['key']}",
                "Value": param["value"],
            }
        )

    # Build step function input json
    sfn_input_json = json.dumps(
        {
            **{
                "productOperationRequest": op_req,
            },
            **{
                "codebuild": {
                    "environmentVariablesOverride": codebuild_env_vars,
                },
            },
        },
        default=str,
    )
    print("state machine input json:")
    print(sfn_input_json)

    if op_req["operation"] == "PROVISION_PRODUCT":
        operation_short_name = "provision"
    elif op_req["operation"] == "UPDATE_PROVISIONED_PRODUCT":
        operation_short_name = "update"
    elif op_req["operation"] == "TERMINATE_PROVISIONED_PRODUCT":
        operation_short_name = "terminate"
    else:
        operation_short_name = "unknown-operation"

    # Start product operation state machine with input
    start_sfn_args = {
        "stateMachineArn": os.environ["STATE_MACHINE_ARN"],
        # setting name makes execution easier to find in sfn execution history
        "name": f"{operation_short_name}-{op_req['provisionedProductId']}-{op_req['recordId']}",
        # merge product operation with generated
        "input": sfn_input_json,
    }
    print("starting state machine execution with arguments:")
    print(json.dumps(start_sfn_args, default=str))
    sfn.start_execution(**start_sfn_args)
