import json
import boto3

sc = boto3.client("servicecatalog")
s3 = boto3.resource("s3")


def handler(event, context):
    print(json.dumps(event, default=str))
    op_req = event["productOperationRequest"]
    operation = op_req["operation"]

    notify_args = {
        "WorkflowToken": op_req["token"],
        "RecordId": op_req["recordId"],
        "Status": "SUCCEEDED",
    }

    # For provision + update operations, download tfoutputs.json from S3 and build Outputs into notify args
    if operation in ["PROVISION_PRODUCT", "UPDATE_PROVISIONED_PRODUCT"]:
        cb_env_vars = event["codebuild"]["environmentVariablesOverride"]
        tf_outputs_s3_uri = {v["Name"]: v["Value"] for v in cb_env_vars}["OUTPUTS_S3_URI"]

        print("loading terraform outputs json from s3 uri:", tf_outputs_s3_uri)
        tf_outputs_json = s3_get_object(tf_outputs_s3_uri)

        print("terraform outputs json:")
        print(tf_outputs_json)
        tf_outputs = json.loads(tf_outputs_json)
        sc_outputs = []
        for tf_output_key, tf_output in tf_outputs.items():
            value = tf_output["value"]
            # return non-string values as json string
            if value.__class__ != str:
                value = json.dumps(value, default=str)
            sc_outputs.append(
                {
                    "OutputKey": tf_output_key,
                    "OutputValue": value,
                    "Description": tf_output.get("description", "No description provided"),
                }
            )

        notify_args["Outputs"] = sc_outputs

    # PROVISION_PRODUCT operation requires at least one ResourceIdentifier:
    #   InvalidParametersException: A ResourceIdentifier is required for a workflow Status of 'SUCCEEDED'.
    if operation == "PROVISION_PRODUCT":
        # TODO: attempt to load resource ids from tfoutputs.json? Would require a standard output convention to be
        # followed. The only benefit to this is ServiceCatalog creates a resource group with the provided resource ids.
        notify_args["ResourceIdentifier"] = {
            "UniqueTag": {"Key": "Arn", "Value": "arn:placeholder:not:a:real:arn"},
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
