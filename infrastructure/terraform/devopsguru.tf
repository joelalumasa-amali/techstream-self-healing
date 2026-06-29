resource "aws_devopsguru_service_integration" "main" {
  ops_center {
    opt_in_status = "ENABLED"
  }
}

resource "aws_devopsguru_resource_collection" "main" {
  type = "AWS_CLOUD_FORMATION"

  cloudformation {
    stack_names = ["*"]
  }
}
