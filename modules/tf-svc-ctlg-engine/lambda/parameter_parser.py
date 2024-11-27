import json
import boto3
import os
import zipfile
import shutil

sts = boto3.client("sts")


# Example event:
# {
#     "artifact": {
#         "path": "s3://sc-1f4e39d8d6ee2486532d12570660174a-us-gov-west-1/out/7a4b8a59bd08f838400ad80309444392/60413ed8e0ba1e67a89ecd3b1f2280e9-466c76bf1ec0618e4672d8061734b1c2473207d1d225e2cde200bece3f37ef50-bb6b1286bd6031a333ce4ecd6285008449134e044ee16407f8090cc7c5db13d9-1732556832175-7e12aeec-f913-4833-b819-8fd4a9c5be56",
#         "type": "AWS_S3"
#     },
#     "launchRoleArn": "arn:aws:iam::111111111111:role/ServiceCatalogLaunchRole"
# }
def handler(event, context):
    print(json.dumps(event, default=str))

    if event["artifact"]["type"] != "AWS_S3":
        raise Exception(f"Error: Unknown artifact type '{event['artifact']['type']}', expected 'AWS_S3'")

    session = assume_role(event["launchRoleArn"])
    s3 = session.client("s3")

    s3_uri_parts = event["artifact"]["path"].removeprefix("s3://").split("/")
    bucket = s3_uri_parts.pop(0)
    object_key = "/".join(s3_uri_parts)
    local_artifact_path = "/tmp/" + context.aws_request_id
    local_artifact_path_zip = local_artifact_path + ".zip"

    print("downloading file from bucket", bucket, "key", object_key, "to local path", local_artifact_path_zip)
    s3.download_file(bucket, object_key, local_artifact_path_zip)

    print("extracting files from", local_artifact_path_zip, "to", local_artifact_path)
    with zipfile.ZipFile(local_artifact_path_zip, "r") as zip_ref:
        zip_ref.extractall(local_artifact_path)

    print("delete zip artifact", local_artifact_path_zip)
    os.remove(local_artifact_path_zip)

    print("extracted files to", local_artifact_path)
    for dirpath, dirnames, filenames in os.walk(local_artifact_path):
        print(dirpath, "dirnames:", dirnames, "filenames:", filenames)

    variables_file_path = os.path.join(local_artifact_path, os.environ["VARIABLES_TF_JSON_FILENAME"])
    print("loading variables from file", variables_file_path)
    try:
        with open(variables_file_path) as vars_file:
            artifact_variables = json.load(vars_file).get("variable", {})
    except Exception as e:
        raise Exception(
            f"Provisioning artifact (product version) parameters could not be loaded from file '{os.environ['VARIABLES_TF_JSON_FILENAME']}'"
        ) from e

    print("deleting directory", local_artifact_path)
    shutil.rmtree(local_artifact_path)

    resp = {"parameters": []}
    for var_name, var_block in artifact_variables.items():
        # return non-string default values as json string
        default_value = var_block.get("default", "")
        if default_value.__class__ != str:
            default_value = json.dumps(default_value, default=str)

        # Documentation claims 'description', 'defaultValue', and 'isNoEcho' are optional, however omitting any of these
        # raises error "Unable to parse or process ServiceCatalogExternalParameterParser lambda response as JSON object"
        p = {
            "key": var_name,
            "type": var_block.get("type", "any"),
            "description": var_block.get("description", "No description provided"),
            "defaultValue": default_value,
            "isNoEcho": var_block.get("sensitive", False),
        }

        resp["parameters"].append(p)

    print("returning response", resp)
    return resp


def assume_role(role_arn):
    # create client in each account for assume role
    creds = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "cross-acct"),
    )["Credentials"]

    # create a license manager boto3 session using credentials in other account
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )
