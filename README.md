# TechStream Self-Healing System

A self-healing infrastructure system that monitors Golden Signals, detects anomalies, and automatically remediates incidents before waking up an engineer.

## Objectives

- Implement Golden Signal monitoring (Latency, Traffic, Errors, Saturation)
- Simulate an incident and trigger automated remediation
- Use AI/ML for root cause analysis via Amazon DevOps Guru

## Architecture

A Flask web server on EC2 emits custom CloudWatch metrics. When error rate exceeds threshold, an alarm triggers EventBridge which invokes a Lambda that automatically restarts the service via SSM Run Command.

## Part 1 — Monitoring Stack

Flask app deployed on EC2 (t3.micro) emits four Golden Signal metrics to CloudWatch under the TechStream namespace. A CloudWatch dashboard visualizes all four signals in real time.

## Part 2 — Anomaly Injection

A chaos script sends 20 HTTP requests to the /error endpoint, generating artificial errors that spike the ErrorCount metric and trigger the alarm.

## Part 3 — Alerting and Remediation

CloudWatch alarm fires when ErrorCount exceeds 5 per minute. EventBridge rule detects the alarm state change and invokes the remediation Lambda. Lambda sends an SSM Run Command to restart the techstream systemd service on the EC2 instance automatically.

## Part 4 — AI Analysis

Amazon DevOps Guru enabled with CloudFormation resource collection. DevOps Guru baselines the stack metrics and generates anomaly insights when the chaos script is triggered.

## Infrastructure (Terraform)

- EC2 instance with IAM role for CloudWatch and SSM
- Security group allowing HTTP on port 5000
- CloudWatch dashboard with Golden Signals
- CloudWatch alarm on ErrorCount threshold
- SNS topic for alert notifications
- EventBridge rule targeting remediation Lambda
- Lambda function with SSM permissions
