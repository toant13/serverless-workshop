provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.region}"
}

variable "access_key" {
}
variable "secret_key" {
}
variable "region" {
  default = "us-east-1"
}

resource "aws_s3_bucket" "serverless-video-upload" {
  bucket = "${var.serverless-video-upload}"
  acl = "private"

  force_destroy = false

  versioning {
    enabled = true
  }

  tags {
    Name = "serverless-video-upload-s3-bucket"
    Environment = "${var.environment}"
  }
}

resource "aws_s3_bucket" "serverless-video-transcoded" {
  bucket = "${var.serverless-video-transcoded}"
  acl = "private"

  force_destroy = false

  versioning {
    enabled = true
  }
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AddPerm",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${var.serverless-video-transcoded}/*"
    }
  ]
}
EOF

  tags {
    Name = "serverless-video-transcoded-s3-bucket"
    Environment = "${var.environment}"
  }
}

resource "aws_iam_role" "lambda-s3-execution-role" {
  name = "${var.lambda-s3-execution-role}-${var.environment}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "AWS-Lambda-Execute-Manage-Policy" {
  name = "AWS-Lambda-Execute-Manage-Policy"
  roles = [
    "${aws_iam_role.lambda-s3-execution-role.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

resource "aws_iam_policy_attachment" "AWS-Elastic-Transcoder-Jobs-Submitter-Manage-Policy" {
  name = "AWS-Elastic-Transcoder-Jobs-Submitter-Manage-Policy"
  roles = [
    "${aws_iam_role.lambda-s3-execution-role.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticTranscoderJobsSubmitter"
}

resource "aws_iam_role" "elastic-transcoder-execution-role" {
  name = "${var.serverless-elastic-transcoder}-${var.environment}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "elastictranscoder.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "LeadAuthParkHandlerPermissionPolicies" {
  name = "ets-console-generated-policy"
  role = "${aws_iam_role.elastic-transcoder-execution-role.id}"
  policy = <<EOF
{
  "Statement": [
    {
      "Action": [
        "s3:Put*",
        "s3:ListBucket",
        "s3:*MultipartUpload*",
        "s3:Get*"
      ],
      "Effect": "Allow",
      "Resource": "*",
      "Sid": "1"
    },
    {
      "Action": "sns:Publish",
      "Effect": "Allow",
      "Resource": "*",
      "Sid": "2"
    },
    {
      "Action": [
        "s3:*Delete*",
        "s3:*Policy*",
        "sns:*Remove*",
        "sns:*Delete*",
        "sns:*Permission*"
      ],
      "Effect": "Deny",
      "Resource": "*",
      "Sid": "3"
    }
  ],
  "Version": "2008-10-17"
}
EOF
}

resource "aws_elastictranscoder_pipeline" "serverless-elastic-transcoder" {
  input_bucket = "${aws_s3_bucket.serverless-video-upload.bucket}"
  name = "${var.serverless-elastic-transcoder}"
  role = "${aws_iam_role.elastic-transcoder-execution-role.arn}"

  content_config = {
    bucket = "${aws_s3_bucket.serverless-video-transcoded.bucket}"
    storage_class = "Standard"
  }

  thumbnail_config = {
    bucket = "${aws_s3_bucket.serverless-video-transcoded.bucket}"
    storage_class = "Standard"
  }
}

resource "aws_lambda_function" "serverless-transcode-video-lambda" {
  filename = "../lambda/video-transcoder/Lambda-Deployment.zip"
  source_code_hash = "${base64sha256(file("../lambda/video-transcoder/Lambda-Deployment.zip"))}"
  function_name = "${var.serverless-transcode-video-lambda}"
  description = "transcodes videos from upload bucket and then puts them into the transcode bucket"
  role = "${aws_iam_role.lambda-s3-execution-role.arn}"
  handler = "index.handler"
  runtime = "nodejs6.10"
  timeout = 80
  memory_size = 128
  environment = {
    variables = {
      ELASTIC_TRANSCODER_REGION = "us-east-1",
      ELASTIC_TRANSCODER_PIPELINE_ID = "${aws_elastictranscoder_pipeline.serverless-elastic-transcoder.id}"
    }
  }

  depends_on = [
    "aws_iam_role.lambda-s3-execution-role"]
}

resource "aws_lambda_permission" "serverless-video-upload-lambda-permission" {
  statement_id = "serverless-video-upload-lambda-permission"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.serverless-transcode-video-lambda.function_name}"
  principal = "s3.amazonaws.com"
  source_arn = "${aws_s3_bucket.serverless-video-upload.arn}"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.serverless-video-upload.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.serverless-transcode-video-lambda.arn}"
    events              = ["s3:ObjectCreated:*"]
  }
}