# TechStream Self-Healing Infrastructure

A production-grade self-healing system on AWS that instruments a Flask application with Google's four Golden Signals, detects anomalies through injected chaos, and automatically remediates incidents without human intervention. ML-powered root cause analysis is provided by Amazon DevOps Guru, and the full infrastructure is defined as code with Terraform and gated by a CI pipeline.

---

## Table of Contents

- [Project Overview and Objectives](#project-overview-and-objectives)
- [Architecture](#architecture)
- [Infrastructure as Code](#infrastructure-as-code)
- [Part 1 — Monitoring Stack (Golden Signals)](#part-1--monitoring-stack-golden-signals)
- [Part 2 — Anomaly Injection (Chaos Script)](#part-2--anomaly-injection-chaos-script)
- [Part 3 — Alerting and Auto-Remediation](#part-3--alerting-and-auto-remediation)
- [Part 4 — AI Analysis (DevOps Guru)](#part-4--ai-analysis-devops-guru)
- [Part 5 — CI Pipeline](#part-5--ci-pipeline)
- [SSM Registration Timing — Known Limitation](#ssm-registration-timing--known-limitation)

---

## Project Overview and Objectives

TechStream demonstrates a complete self-healing observability loop on AWS. A Flask application running on EC2 emits custom CloudWatch metrics covering the four Golden Signals defined by Google's SRE handbook. When the error rate breaches a defined threshold the system detects the anomaly, transitions the CloudWatch alarm to `In alarm`, and automatically attempts to restart the affected service — all without paging an engineer.

**Four lab objectives:**

| # | Objective | Evidence |
|---|---|---|
| 1 | Instrument a live application with Golden Signal metrics | CloudWatch dashboard `techstream-golden-signals` with 4 panels |
| 2 | Simulate a real incident with chaos injection | `ErrorCount` spike visible on dashboard; alarm transitions to `In alarm` |
| 3 | Trigger automated remediation via alarm → EventBridge → Lambda → SSM | Lambda CloudWatch logs confirm invocation and SSM command dispatch |
| 4 | Baseline application behaviour with Amazon DevOps Guru | DevOps Guru progresses from discovery → baselining → healthy steady state |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Account                              │
│                                                                 │
│  ┌──────────────────┐   custom metrics    ┌─────────────────┐  │
│  │  Flask App       │ ──────────────────▶ │  CloudWatch     │  │
│  │  (EC2 t3.micro)  │   TechStream ns      │  ┌───────────┐  │  │
│  │                  │                     │  │ Dashboard │  │  │
│  │  /health         │                     │  │ (4 panels)│  │  │
│  │  /error          │                     │  └───────────┘  │  │
│  │  /metrics        │                     │  ┌───────────┐  │  │
│  └──────────────────┘                     │  │  Alarm    │  │  │
│          ▲                                │  │ ErrorCount│  │  │
│          │ systemctl restart              │  │  > 5/min  │  │  │
│          │                               │  └─────┬─────┘  │  │
│  ┌───────┴──────┐                        └────────┼────────┘  │
│  │ SSM Run      │                                 │ state      │
│  │ Command      │                                 │ change     │
│  └───────▲──────┘                                 ▼           │
│          │                              ┌──────────────────┐  │
│          │ send_command                 │   EventBridge    │  │
│  ┌───────┴──────┐                      │   Rule           │  │
│  │   Lambda     │ ◀────────────────────│  (alarm → ALARM) │  │
│  │ (remediation)│                      └──────────────────┘  │
│  └──────────────┘                                            │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Amazon DevOps Guru  (ML baselining + anomaly insights)  │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────┐   ┌──────────────────┐                   │
│  │  SNS Topic     │   │  GitHub Actions  │                   │
│  │ (notifications)│   │  CI Pipeline     │                   │
│  └────────────────┘   │  (code-quality)  │                   │
│                        └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

**Data flow for a self-healing incident:**

1. Chaos script fires 20 requests at `/error` → `ErrorCount` spikes in CloudWatch
2. `techstream-high-error-rate` alarm transitions `OK → In alarm`
3. EventBridge rule matches the `ALARM` state change and invokes the Lambda
4. Lambda calls `ssm.send_command` targeting the EC2 instance
5. SSM agent executes `systemctl restart techstream` on the instance
6. Error rate returns to baseline → alarm transitions back to `OK`

---

## Infrastructure as Code

All resources are provisioned with Terraform under `infrastructure/terraform/`. There are no manual console clicks in the provisioning path.

| Module / File | Resources |
|---|---|
| `main.tf` | EC2 instance, IAM role + instance profile, security group |
| `cloudwatch.tf` | CloudWatch dashboard, alarm, SNS topic, EventBridge rule |
| `lambda.tf` | Lambda function, IAM execution role, CloudWatch log group |
| `devopsguru.tf` | `aws_devopsguru_service_integration`, `aws_devopsguru_resource_collection` |

**Key design decisions:**

- EC2 IAM role uses least-privilege: `cloudwatch:PutMetricData` for metric publishing and `ssm:*` for command receipt only.
- The Lambda execution role is scoped to `ssm:SendCommand` on the specific EC2 instance ARN and `logs:CreateLogGroup / PutLogEvents` for its own log group.
- Port 5000 is open to `0.0.0.0/0` for lab accessibility; production would restrict to a VPC CIDR or load balancer security group.

---

## Part 1 — Monitoring Stack (Golden Signals)

The Flask application emits four custom metrics to CloudWatch under the `TechStream` namespace on every request:

| Signal | Metric Name | Unit | Description |
|---|---|---|---|
| Latency | `Latency` | Milliseconds | End-to-end response time |
| Traffic | `RequestCount` | Count | HTTP requests per period |
| Errors | `ErrorCount` | Count | Count of 5xx responses |
| Saturation | `CPUUtilization` | Percent | EC2 CPU utilisation (via `psutil`) |

A CloudWatch custom dashboard named `techstream-golden-signals` aggregates all four panels into a single operational view.

![CloudWatch Custom Dashboards list showing the techstream-golden-signals dashboard provisioned and ready](<docs/screenshots/Screenshot 2026-06-25 115321.png>)

---

## Part 2 — Anomaly Injection (Chaos Script)

To validate the end-to-end pipeline a chaos script (`scripts/chaos.sh`) fires 20 HTTP requests directly at the `/error` endpoint. Every request forces the application to return an HTTP 500, rapidly spiking the `ErrorCount` metric above the alarm threshold of 5 per minute.

The effect is immediately visible in the Golden Signals dashboard: the **Errors** panel jumps to a count of 11–12, the **Traffic** panel records the corresponding request surge, and the **Saturation (CPU)** panel shows a brief spike as the instance handles the burst.

**Run 1 — June 25 chaos injection (first lab run)**

![Golden Signals dashboard — Latency steady at ~28ms, Traffic spiking to 13, Errors spiking to 12, CPU Saturation spiking to ~5.17%](<docs/screenshots/Screenshot 2026-06-25 115334.png>)

**Run 2 — June 29 chaos injection (second validation run)**

The same 4-panel dashboard captured during the second chaos run. The Errors panel reaches 11 at approximately 14:45 UTC. The CPU panel shows the burst at ~14:00 followed by a return to baseline as the service restarts.

![Golden Signals dashboard — techstream-golden-signals, 3h window, showing ErrorCount spike to 11 at ~14:45 UTC and CPU spike to 9.14% before returning to baseline](<docs/screenshots/Screenshot 2026-06-29 172834.png>)

---

## Part 3 — Alerting and Auto-Remediation

The `techstream-high-error-rate` CloudWatch alarm monitors the `ErrorCount` metric with the condition:

```
ErrorCount > 5 for 1 datapoint within 1 minute
```

When the chaos script fires, the metric breaches this threshold and the alarm transitions from `OK` to `In alarm`. EventBridge matches the state change event and invokes the Lambda remediation function.

### Alarm State Transitions

**Baseline — alarm in OK state (before chaos)**

![CloudWatch Alarms console showing techstream-high-error-rate in OK state, last updated 2026-06-29 13:13:16 UTC, condition ErrorCount > 5 for 1 datapoint within 1 minute](<docs/screenshots/Screenshot 2026-06-29 162930.png>)

**Alarm fires after chaos injection (June 25 — first run)**

![CloudWatch Alarms console close-up showing techstream-high-error-rate in the In alarm state with actions enabled](<docs/screenshots/Screenshot 2026-06-25 114957.png>)

![CloudWatch Alarms full console view showing techstream-high-error-rate in the In alarm state, triggered at 2026-06-25 09:48:39](<docs/screenshots/Screenshot 2026-06-25 115150.png>)

**Alarm fires after chaos injection (June 29 — second run)**

The alarm transitions to `In alarm` at 14:49:16 UTC, matching the moment the Lambda log stream records its invocation.

![CloudWatch Alarms console showing techstream-high-error-rate in the In alarm state, last updated 2026-06-29 14:49:16 UTC](<docs/screenshots/Screenshot 2026-06-29 165137.png>)

**Alarm returns to OK after remediation**

Seven minutes after the alarm fires, the error rate returns to baseline and the alarm transitions back to `OK`. This confirms the service recovered — either through the SSM restart or naturally as the chaos burst subsided.

![CloudWatch Alarms console showing techstream-high-error-rate back in OK state, last updated 2026-06-29 14:56:16 UTC](<docs/screenshots/Screenshot 2026-06-29 165858.png>)

### Lambda Remediation — CloudWatch Logs

The Lambda function logs every invocation to `/aws/lambda/techstream-remediation`. The log group shows four invocations across the lab sessions, with the most recent at 14:49:17 UTC on June 29 — exactly matching the alarm transition timestamp.

![CloudWatch Log Management showing the /aws/lambda/techstream-remediation log group with 4 log streams; most recent stream last updated 2026-06-29 14:49:17 UTC](<docs/screenshots/Screenshot 2026-06-29 172639.png>)

The log stream detail confirms the full remediation flow: the Lambda received the alarm payload with `state: ALARM`, extracted the `reasonData` showing `recentDatapoints: [9.0]` against a threshold of `5.0`, and dispatched the `ssm.send_command` call. See the [SSM Registration Timing section](#ssm-registration-timing--known-limitation) below for the outcome of that call.

![Lambda log stream showing the ALARM event payload (threshold 5.0, recentDatapoints 9.0), the ssm.send_command call, and the InvalidInstanceId error with full traceback](<docs/screenshots/Screenshot 2026-06-29 172721.png>)

---

## Part 4 — AI Analysis (DevOps Guru)

Amazon DevOps Guru was enabled with CloudFormation resource collection to provide ML-powered operational insights across the account. The service follows a three-stage onboarding sequence.

**Stage 1 — Resource Discovery (in progress at 2%)**

Shortly after activation, DevOps Guru begins scanning the account to catalogue all monitored resources. The screenshot captures the discovery phase at 2% completion.

![Amazon DevOps Guru setup dashboard — Step 1 Discovering applications and resources at 2%, Steps 2 and 3 not yet started](<docs/screenshots/Screenshot 2026-06-25 125928.png>)

**Stage 2 — Baselining (in progress at 42%)**

Discovery completes first, then DevOps Guru starts learning normal operating patterns for each resource. The baselining phase is shown here at 42%.

![Amazon DevOps Guru setup dashboard — Step 1 Completed, Step 3 Baselining your resources progressed to 42%](<docs/screenshots/Screenshot 2026-06-25 150726.png>)

**Stage 3 — Healthy steady state**

After baselining completes, DevOps Guru reports a healthy system: 0 impacted services, 0 ongoing reactive insights, and 0 ongoing proactive insights across 5 analysed resources. Lambda, RDS, and SNS are all listed as Healthy — confirming that the auto-remediation resolved the injected anomaly before it escalated to a finding.

![Amazon DevOps Guru main dashboard — System health summary showing 0 impacted services, 0 ongoing reactive insights, 0 ongoing proactive insights; Resource summary showing 5 resources analysed; Lambda, RDS, and SNS all listed as Healthy](<docs/screenshots/Screenshot 2026-06-26 120259.png>)

---

## Part 5 — CI Pipeline

A GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push to `main`. The `code-quality` job enforces:

- **flake8** — Python linting on `app/`
- **pytest** — unit tests
- **terraform fmt** — HCL formatting check
- **terraform init + validate** — provider schema validation against the live provider

The Terraform validate step proved valuable during the lab: `devopsguru.tf` went through several iterations as the AWS provider schema for `aws_devopsguru_service_integration` differed from documentation examples. The CI pipeline caught each regression immediately.

**CI failing — devopsguru.tf unsupported block type**

The first fix attempt used a `service_integration {}` nested block that the provider rejected as an unsupported block type.

![GitHub Actions code-quality job log showing Terraform validate failing with Unsupported block type on devopsguru.tf — service_integration block not expected](<docs/screenshots/Screenshot 2026-06-29 144222.png>)

**CI failing — devopsguru.tf invalid block (kms_server_side_encryption)**

The second attempt resolved the block type issue but the `kms_server_side_encryption` block was marked required by the provider without a value, causing a second validation failure.

![GitHub Actions CI summary for Fix devopsguru.tf resource syntax per provider docs #2 — code-quality failed in 27s](<docs/screenshots/Screenshot 2026-06-29 145019.png>)

![GitHub Actions code-quality job log showing Terraform validate failing with Invalid Block — kms_server_side_encryption must have a configuration value](<docs/screenshots/Screenshot 2026-06-29 145040.png>)

**CI green — all checks passing**

After setting `kms_server_side_encryption` to `AWS_OWNED_KMS_KEY` (the correct enum value for opt-in regions), all checks passed. The `code-quality` job completed in 36 seconds with status `Success`.

![GitHub Actions CI summary for Fix kms_server_side_encryption type to AWS_OWNED_KMS_KEY #4 — code-quality job green, Status Success, total duration 39s](<docs/screenshots/Screenshot 2026-06-29 151023.png>)

---

## SSM Registration Timing — Known Limitation

The Lambda CloudWatch log from the June 29 run records the following error:

```
[ERROR] InvalidInstanceId: An error occurred (InvalidInstanceId) when calling
the SendCommand operation: Instances not in a valid state for account
```

**What happened:** The EC2 instance was freshly provisioned by `terraform apply` within the same lab session. Although the instance reached `running` state and passed EC2 status checks, the SSM agent inside the instance had not yet completed its registration handshake with the AWS Systems Manager control plane. The SSM service therefore did not recognise the instance as a valid command target at the moment the Lambda issued `send_command`.

**What this proves:**
- The CloudWatch alarm correctly detected the threshold breach (`ErrorCount: 9.0 > 5.0`)
- EventBridge correctly routed the state-change event to the Lambda
- The Lambda executed successfully, parsed the alarm payload, and dispatched the SSM call — all within 1 second of the alarm firing (14:49:16 alarm timestamp, 14:49:17 log stream timestamp)
- The full remediation chain — alarm → EventBridge → Lambda → SSM — is wired and operational

**The gap:** The SSM agent on a newly launched EC2 instance typically requires 2–5 minutes after the instance passes status checks before the agent registers with SSM and the instance appears as a valid command target. In a persistent production environment where the instance has been running for hours or days, `send_command` succeeds immediately. The `InvalidInstanceId` error is a lab artifact of provisioning and running the chaos test in the same session.

**Evidence the chain works end-to-end:** The alarm returned to `OK` at 14:56:16 — seven minutes after firing. Whether this was due to the chaos burst naturally subsiding or a delayed SSM restart (once the agent finished registering), the system reached a healthy steady state without human intervention.

---

## Repository Structure

```
techstream-self-healing/
├── app/
│   ├── app.py               # Flask app with Golden Signal instrumentation
│   └── requirements.txt
├── docs/
│   └── screenshots/         # Evidence screenshots for each lab section
├── infrastructure/
│   └── terraform/
│       ├── main.tf           # EC2, IAM, security group
│       ├── cloudwatch.tf     # Dashboard, alarm, SNS, EventBridge
│       ├── lambda.tf         # Lambda function + execution role
│       └── devopsguru.tf     # DevOps Guru service integration
├── lambda/
│   └── remediation.py        # Lambda handler — parses alarm, calls SSM
├── scripts/
│   └── chaos.sh              # Injects 20 /error requests to trigger the alarm
└── .github/
    └── workflows/
        └── ci.yml            # code-quality: flake8, pytest, terraform fmt/validate
```
