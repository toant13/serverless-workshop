provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.region}"
}

//variable "accountId" {}

variable "access_key" {
}
variable "secret_key" {
}
variable "region" {
  default = "us-east-1"
}

data "aws_caller_identity" "current" {}

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

  cors_rule {
    allowed_origins = ["*"]
    allowed_methods = ["GET","POST"]
    max_age_seconds = 3000
    allowed_headers = ["*"]
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
    "${aws_iam_role.lambda-s3-execution-role.name}"
  ]
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
  filename = "../lab-1/lambda/video-transcoder/Lambda-Deployment.zip"
  source_code_hash = "${base64sha256(file("../lab-1/lambda/video-transcoder/Lambda-Deployment.zip"))}"
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
    events = [
      "s3:ObjectCreated:*"]
  }
}

/* ******************* LAB 3 RESOURCES ******************* */

resource "aws_lambda_function" "serverless-user-profile-lambda" {
  filename = "../lab-3/lambda/user-profile/Lambda-Deployment.zip"
  source_code_hash = "${base64sha256(file("../lab-3/lambda/user-profile/Lambda-Deployment.zip"))}"
  function_name = "${var.serverless-user-profile-lambda}"
  description = "talks to Auth0 and retrieves user info"
  role = "${aws_iam_role.lambda-s3-execution-role.arn}"
  handler = "index.handler"
  runtime = "nodejs6.10"
  timeout = 80
  memory_size = 128
  environment = {
    variables = {
      AUTH0_DOMAIN = "${var.auth0-domain}"
    }
  }

  depends_on = [
    "aws_iam_role.lambda-s3-execution-role"]
}

resource "aws_api_gateway_rest_api" "api-gateway-24-hour-video" {
  name = "${var.api-gateway-24-hour-video}"
  description = "24-hour-video-api"
  depends_on = [
    "aws_lambda_function.serverless-user-profile-lambda"]
}

resource "aws_api_gateway_resource" "api-resource-user-profile" {
  rest_api_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
  parent_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.root_resource_id}"
  path_part = "user-profile"
}

resource "aws_lambda_permission" "api-gateway-trigger-user-profile" {
  statement_id = "AllowExecutionFromAPIGateway"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.serverless-user-profile-lambda.arn}"
  principal = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}/*/${aws_api_gateway_method.api-gateway-method-user-profile.http_method}/resourcepath/subresourcepath"
}

//resource "aws_api_gateway_integration" "integration" {
//  rest_api_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
//  resource_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.root_resource_id}"
//  http_method = "${aws_api_gateway_method.api-gateway-method-user-profile.http_method}"
//  integration_http_method = "POST"
//  type = "AWS"
//  //  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.serverless-user-profile-lambda.arn}/invocations"
//  source_arn = "arn:aws:execute-api:${var.region}:${var.accountId}:${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}/*/${aws_api_gateway_method.api-gateway-method-user-profile.http_method}/resourcepath/subresourcepath"
//}

resource "aws_iam_role" "api-gateway-lambda-exec-role" {
  name = "${var.api-gateway-lambda-exec-role}-${var.environment}"
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


resource "aws_iam_policy_attachment" "AWS-API-Gateway-lsLambda-Execute-Manage-Policy" {
  name = "AWS-Lambda-Execute-Manage-Policy"
  roles = [
    "${aws_iam_role.api-gateway-lambda-exec-role.name}"
  ]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "serverless-custom-authorizer-lambda" {
  filename = "../lab-3/lambda/custom-authoriser/Lambda-Deployment.zip"
  source_code_hash = "${base64sha256(file("../lab-3/lambda/custom-authoriser/Lambda-Deployment.zip"))}"
  function_name = "${var.serverless-custom-authorizer-lambda}"
  description = "custom authorizer"
  role = "${aws_iam_role.api-gateway-lambda-exec-role.arn}"
  handler = "index.handler"
  runtime = "nodejs6.10"
  timeout = 80
  memory_size = 128
  environment = {
    variables = {
      AUTH0_SECRET = "OkCdmhb-YjOlBpe3n0tmVpjScmO6f41x75uH-qs-NMXORnDMIs16u_nClpqtNIM0"
    }
  }

  depends_on = [
    "aws_iam_role.api-gateway-lambda-exec-role"]
}

resource "aws_api_gateway_authorizer" "custom-authorizer" {
  name                   = "custom-authorizer"
  rest_api_id            = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
  authorizer_uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.serverless-custom-authorizer-lambda.arn}/invocations"
  authorizer_result_ttl_in_seconds = "300"
}

resource "aws_api_gateway_method" "api-gateway-method-user-profile" {
  rest_api_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
  resource_id = "${aws_api_gateway_resource.api-resource-user-profile.id}"
  http_method = "GET"
  authorization = "CUSTOM"
  authorizer_id = "${aws_api_gateway_authorizer.custom-authorizer.id}"
  depends_on = ["aws_api_gateway_authorizer.custom-authorizer"]
}


/* ******************* LAB 4 RESOURCES ******************* */


resource "aws_lambda_function" "serverless-get-upload-policy-lambda" {
  filename = "../lab-4/lambda/create-s3-upload-policy-document/Lambda-Deployment.zip"
  source_code_hash = "${base64sha256(file("../lab-4/lambda/create-s3-upload-policy-document/Lambda-Deployment.zip"))}"
  function_name = "${var.serverless-get-upload-policy-lambda}"
  description = "upload policy"
  role = "${aws_iam_role.lambda-s3-execution-role.arn}"
  handler = "index.handler"
  runtime = "nodejs6.10"
  timeout = 80
  memory_size = 128
  environment = {
    variables = {
      ACCESS_KEY_ID  = "${aws_iam_access_key.upload-s3-key.id}",
      SECRET_ACCESS_KEY   = "${aws_iam_access_key.upload-s3-key.secret}",
      UPLOAD_BUCKET = "${aws_s3_bucket.serverless-video-upload.bucket}"
    }
  }

  depends_on = [
    "aws_iam_role.lambda-s3-execution-role",
    "aws_iam_user.upload-s3"]
}

resource "aws_iam_user" "upload-s3" {
  name = "upload-s3"
}

resource "aws_iam_access_key" "upload-s3-key" {
  user    = "${aws_iam_user.upload-s3.name}"
}


resource "aws_iam_user_policy" "upload-policy" {
  name = "upload-policy"
  user = "${aws_iam_user.upload-s3.name}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.serverless-video-upload.bucket}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.serverless-video-upload.bucket}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_api_gateway_resource" "api-resource-s3-policy-document" {
  rest_api_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
  parent_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.root_resource_id}"
  path_part = "s3-policy-document"
}

resource "aws_api_gateway_method" "api-gateway-method-s3-policy-document" {
  rest_api_id = "${aws_api_gateway_rest_api.api-gateway-24-hour-video.id}"
  resource_id = "${aws_api_gateway_resource.api-resource-s3-policy-document.id}"
  http_method = "GET"
  authorization = "NONE"
//  authorizer_id = "${aws_api_gateway_authorizer.custom-authorizer.id}"
//  depends_on = ["aws_api_gateway_authorizer.custom-authorizer"]
}