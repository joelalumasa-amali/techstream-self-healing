resource "aws_devopsguru_service_integration" "main" {
  ops_center {
    opt_in_status = "ENABLED"
  }

  kms_server_side_encryption {
    opt_in_status = "DISABLED"
    type          = "AWS_OWNED_KMS_KEY"
  }

  logs_anomaly_detection {
    opt_in_status = "DISABLED"
  }
}

resource "aws_devopsguru_resource_collection" "main" {
  type = "AWS_CLOUD_FORMATION"

  cloudformation {
    stack_names = ["*"]
  }
}
