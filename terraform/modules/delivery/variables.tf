variable "env" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for assets"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable S3 object versioning — false in dev, true in prod"
  type        = bool
}

variable "price_class" {
  description = "CloudFront price class — PriceClass_100 for dev (cheaper), PriceClass_All for prod"
  type        = string
  default     = "PriceClass_100"
}
