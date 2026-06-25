resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorCount"
  namespace           = "TechStream"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Error rate exceeded 5 errors per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_dashboard" "golden_signals" {
  dashboard_name = "${var.project_name}-golden-signals"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Latency"
          region  = "us-east-1"
          metrics = [["TechStream", "Latency"]]
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Traffic (Request Count)"
          region  = "us-east-1"
          metrics = [["TechStream", "RequestCount"]]
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Errors"
          region  = "us-east-1"
          metrics = [["TechStream", "ErrorCount"]]
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Saturation (CPU)"
          region  = "us-east-1"
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id]]
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
        }
      }
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_cloudwatch_event_rule" "alarm_trigger" {
  name        = "${var.project_name}-alarm-trigger"
  description = "Trigger remediation when error rate alarm fires"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = ["${var.project_name}-high-error-rate"]
      state = {
        value = ["ALARM"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.alarm_trigger.name
  target_id = "RemediationLambda"
  arn       = aws_lambda_function.remediation.arn
}
