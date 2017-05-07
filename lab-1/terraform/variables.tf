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






