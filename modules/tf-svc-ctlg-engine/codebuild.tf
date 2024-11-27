resource "aws_iam_role" "codebuild" {
  name_prefix = "CodeBuild-TerraformSvcCtlgEngine-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "codebuild.amazonaws.com"
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

resource "aws_iam_role_policy" "codebuild" {
  name_prefix = "Terraform-"
  role        = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
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
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
        ]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/TerraformSvcCtlgEngine"
  retention_in_days = 14
}

resource "aws_codebuild_project" "terraform" {
  name          = "TerraformSvcCtlgEngine"
  description   = "Provision update and destroy Terraform service catalog products"
  build_timeout = 60 # minutes
  service_role  = aws_iam_role.codebuild.arn

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }
    environment_variable {
      name  = "TF_INPUT"
      value = "false"
    }
    environment_variable {
      name  = "TF_LOG"
      value = "ERROR"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOF
      version: 0.2

      phases:
        # install:
        #   runtime-versions:
        #     python: 3.9
        build:
          commands:
          - |
            set -eux
            env | sort
            aws sts get-caller-identity

            set +u
            # append to TF_CLI_ARGS
            export TF_CLI_ARGS="$TF_CLI_ARGS -no-color"
            env | grep TF_CLI_ARGS
            set -u

            export STDERR_FILE="$CODEBUILD_SRC_DIR/stderr.txt"

            # Install terraform at front of PATH
            mkdir -p /usr/local/bin
            export PATH="/usr/local/bin:$PATH"
            curl -Lso /tmp/terraform.zip 'https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip'
            unzip /tmp/terraform.zip terraform -d /usr/local/bin
            chmod +x /usr/local/bin/terraform
            terraform -version

            # Print stderr, publish stderr to s3, then exit 1
            handle_tf_error() {
              echo "Terraform error encountered"
              unset AWS_PROFILE
              if [[ -s "$STDERR_FILE" ]]; then
                echo "$STDERR_FILE:"
                cat "$STDERR_FILE"
                aws s3 cp "$STDERR_FILE" "$STDERR_S3_URI"
              fi
              exit 1
            }

            # Reset AWS config file, configure default (codebuild role) profile and launch-role profile
            rm -f ~/.aws/config
            # create the default profile with no real configuration
            aws --profile default configure set output json
            # create the launch-role profile to assume the launch role
            aws --profile launch-role configure set credential_source EcsContainer
            aws --profile launch-role configure set role_arn "$LAUNCH_ROLE_ARN"

            # launch-role profile used to download artifact from s3, and terraform resource provisioning
            export AWS_PROFILE='launch-role'
            aws sts get-caller-identity

            # Terminate operation does not provide artifact to download, create .tf.json file with aws provider
            if [[ "$OPERATION" == 'TERMINATE_PROVISIONED_PRODUCT' ]]; then
              GENERATED_AWS_PROVIDER='{"terraform": {"required_providers": {"aws": {"source": "hashicorp/aws"}}}}'
              echo "$GENERATED_AWS_PROVIDER" | tee generated_aws_provider.tf.json

            # For non-terminate operations, download terraform artifact from s3 unzipped into current directory
            else
              aws s3 cp "$ARTIFACT_S3_URI" '/tmp/artifact.zip'
              unzip /tmp/artifact.zip -d .
              find . -type f
            fi

            # Configure terraform s3 backend (provided to build in env var as .tf.json)
            echo "$S3_BACKEND_JSON" | tee generated_s3_backend.tf.json

            # Run terraform commands, handle errors
            if ! terraform init                              2> stderr.txt; then handle_tf_error; fi
            if ! terraform apply -auto-approve               2> stderr.txt; then handle_tf_error; fi
            if ! terraform output -json | tee tfoutputs.json 2> stderr.txt; then handle_tf_error; fi

            # default profile used to publish outputs to s3
            unset AWS_PROFILE
            aws s3 cp tfoutputs.json "$OUTPUTS_S3_URI"
    EOF
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  # cache {
  #   type     = "S3"
  #   location = aws_s3_bucket.example.bucket
  # }

  # vpc_config {
  #   vpc_id = aws_vpc.example.id

  #   subnets = [
  #     aws_subnet.example1.id,
  #     aws_subnet.example2.id,
  #   ]

  #   security_group_ids = [
  #     aws_security_group.example1.id,
  #     aws_security_group.example2.id,
  #   ]
  # }
}
