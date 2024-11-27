resource "aws_s3_bucket" "tfstate" {
  bucket_prefix = "tfstate-${local.acct_id}-${local.region}-"
}
