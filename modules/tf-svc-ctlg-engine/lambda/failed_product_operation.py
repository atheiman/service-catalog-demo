# If this function fails, the provisioned product stays stuck in a change status that cannot be released until
# ServiceCatalog Notify*ProductEngineWorkflowResult api is called manually.

import json
import boto3
import os

sc = boto3.client("servicecatalog")
s3 = boto3.resource("s3")


def handler(event, context):
    print(json.dumps(event, default=str))
    op_req = event["State"]["productOperationRequest"]
    operation = op_req["operation"]

    try:
        error_cause = json.loads(event["State"]["Error"]["Cause"])
        print(json.dumps(error_cause))
    except Exception as e:
        print("Could not load error cause from event:", repr(e))

    addl_failure_info = ""

    # Attempt to load terraform stderr
    try:
        cb_env_vars = event["State"]["codebuild"]["environmentVariablesOverride"]
        tf_stderr_s3_uri = {v["Name"]: v["Value"] for v in cb_env_vars}["STDERR_S3_URI"]
        print("loading terraform stderr:", tf_stderr_s3_uri)
        tf_stderr = s3_get_object(tf_stderr_s3_uri)
        addl_failure_info += tf_stderr
    except Exception as e:
        print("Could not load terraform stderr from s3", repr(e))

    notify_args = {
        "WorkflowToken": op_req["token"],
        "RecordId": op_req["recordId"],
        "Status": "FAILED",
        # FailureReason does not render for the user on PROVISION_PRODUCT operations (Service Catalog bug?).
        # UPDATE_PROVISIONED_PRODUCT and TERMINATE_PROVISIONED_PRODUCT successfully render FailureReason for the user.
        # This can be verified using `aws servicecatalog describe-record --id rec-aaaaaaaa`
        "FailureReason": (
            f"Terraform provisioning Step Functions State Machine failed: {event['Context']['Execution']['Id']} "
            + addl_failure_info
        )[:2048],
    }

    print(f"Notifying servicecatalog of product operation result for operation '{operation}' with args:")
    print(json.dumps(notify_args, default=str))

    if operation == "PROVISION_PRODUCT":
        sc.notify_provision_product_engine_workflow_result(**notify_args)
    elif operation == "UPDATE_PROVISIONED_PRODUCT":
        sc.notify_update_provisioned_product_engine_workflow_result(**notify_args)
    elif operation == "TERMINATE_PROVISIONED_PRODUCT":
        sc.notify_terminate_provisioned_product_engine_workflow_result(**notify_args)
    else:
        raise Exception(f"Unknown product operation '{operation}'")


def s3_get_object(s3_uri):
    parts = s3_uri.removeprefix("s3://").split("/")
    bucket = parts.pop(0)
    key = "/".join(parts)
    return s3.Object(bucket, key).get()["Body"].read().decode("utf-8")
