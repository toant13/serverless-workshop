variable "environment" {
  default = "dev"
}

variable "serverless-video-upload" {
  //enter the preferred name for a upload s3 bucket
  default = "serverlessconf-video-upload"
}

variable "serverless-video-transcoded" {
  //enter the preferred name for a trancoded s3 bucket
  default = "serverlessconf-video-transcoded"
}

variable "lambda-s3-execution-role" {
  default = "lambda-s3-execution-role"
}

variable "serverless-elastic-transcoder" {
  default = "24-hour-video"
}

variable "serverless-transcode-video-lambda" {
  //enter the preferred name for a lambda
  default = "transcode-video"
}

variable "serverless-user-profile-lambda" {
  //enter the preferred name for a lambda
  default = "user-profile"
}

variable "auth0-domain" {
  //enter your auth0 domain created from lab 2 here
  default = "ttran.auth0.com"
}

variable "api-gateway-24-hour-video" {
  default = "24-Hour-Video"
}

variable "api-gateway-lambda-exec-role" {
  default = "api-gateway-lambda-exec-role"
}

variable "serverless-custom-authorizer-lambda" {
  //enter the preferred name for a lambda
  default = "custom-authorizer"
}

variable "serverless-get-upload-policy-lambda" {
  //enter the preferred name for a lambda
  default = "get-upload-policy"
}

variable "serverless-push-transcoded-url-to-firebase-lambda" {
  //enter the preferred name for a lambda
  default = "push-transcoded-url-to-firebase"
}