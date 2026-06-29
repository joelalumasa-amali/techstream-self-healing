resource "aws_devopsguru_service_integration" "main" {
  service_integration {
    ops_center {
      opt_in_status = "ENABLED"
    }
  }
}

resource "aws_devopsguru_resource_collection" "main" {
  type = "AWS_CLOUD_FORMATION"

  cloud_formation {
    stack_names = ["*"]
  }
}
