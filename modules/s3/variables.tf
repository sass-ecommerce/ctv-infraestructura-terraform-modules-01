variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
}

variable "enable_versioning" {
  type        = bool
  default     = true
  description = "Whether to enable versioning on the bucket"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the bucket"
}

variable "lambda_notifications" {
  type = list(object({
    lambda_function_arn = string
    events              = list(string)
    filter_prefix       = optional(string)
    filter_suffix       = optional(string)
  }))
  default     = []
  description = "Lambda function notification configurations for the bucket"
}

variable "sqs_notifications" {
  type = list(object({
    queue_arn     = string
    events        = list(string)
    filter_prefix = optional(string)
    filter_suffix = optional(string)
  }))
  default     = []
  description = "SQS queue notification configurations for the bucket"
}

variable "sns_notifications" {
  type = list(object({
    topic_arn     = string
    events        = list(string)
    filter_prefix = optional(string)
    filter_suffix = optional(string)
  }))
  default     = []
  description = "SNS topic notification configurations for the bucket"
}

variable "enable_eventbridge" {
  type        = bool
  default     = false
  description = "Whether to enable EventBridge notifications for all bucket events"
}
