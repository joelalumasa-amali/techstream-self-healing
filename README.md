# TechStream Self-Healing System

A self-healing infrastructure system built on AWS that monitors Golden Signals in real time, detects anomalies via injected chaos, and automatically remediates incidents without human intervention. The system also integrates Amazon DevOps Guru for ML-powered root cause analysis.

---

## Table of Contents

- [Project Overview and Objectives](#project-overview-and-objectives)
- [Architecture](#architecture)
- [Part 1 — Monitoring Stack (Golden Signals)](#part-1--monitoring-stack-golden-signals)
- [Part 2 — Anomaly Injection (Chaos Script)](#part-2--anomaly-injection-chaos-script)
- [Part 3 — Alerting and Remediation](#part-3--alerting-and-remediation)
- [Part 4 — AI Analysis (DevOps Guru)](#part-4--ai-analysis-devops-guru)

---

## Project Overview and Objectives

TechStream demonstrates a production-grade self-healing pattern on AWS. A Flask application running on EC2 emits custom CloudWatch metrics covering Google's four Golden Signals. When the error rate breaches a defined threshold, the system detects the anomaly, fires an alarm, and automatically restarts the affected service — all without paging an engineer.

**Objectives:**

- Instrument a live application with Golden Signal metrics (Latency, Traffic, Errors, Saturation)
- Simulate a real incident using a chaos injection script
- Trigger automated remediation via CloudWatch Alarms → EventBridge → Lambda → SSM Run Command
- Baseline application behaviour with Amazon DevOps Guru for ML-driven anomaly detection

---

## Architecture

```
Flask App (EC2 t3.micro)
        │
        │  Custom metrics (TechStream namespace)
        ▼
Amazon CloudWatch
  ├── Dashboard: techstream-golden-signals (4 panels)
  ├── Alarm:     techstream-high-error-rate (ErrorCount > 5/min)
  └── EventBridge Rule
              │
              ▼
        Lambda Function
     (remediation handler)
              │
              │  SSM Run Command
              ▼
        EC2 Instance
    (restarts techstream.service)
              │
              ▼
    Amazon DevOps Guru
    (ML baselining + anomaly insights)
```

All infrastructure is provisioned with Terraform. The EC2 instance carries an IAM role granting it the minimum permissions required for CloudWatch metric publishing and SSM command receipt.

**Infrastructure components:**

| Resource | Purpose |
|---|---|
| EC2 (t3.micro) | Hosts the Flask application |
| IAM Role | Grants EC2 access to CloudWatch and SSM |
| Security Group | Opens port 5000 for HTTP traffic |
| CloudWatch Dashboard | Visualises all four Golden Signals |
| CloudWatch Alarm | Fires when ErrorCount exceeds threshold |
| SNS Topic | Delivers alert notifications |
| EventBridge Rule | Routes alarm state changes to Lambda |
| Lambda Function | Executes the SSM restart command |
| Amazon DevOps Guru | ML-powered anomaly analysis |

---

## Part 1 — Monitoring Stack (Golden Signals)

The Flask application emits four custom metrics to CloudWatch under the `TechStream` namespace every time a request is processed:

| Signal | Metric | Description |
|---|---|---|
| Latency | `Latency` | End-to-end response time in milliseconds |
| Traffic | `RequestCount` | Number of HTTP requests per period |
| Errors | `ErrorCount` | Count of 5xx responses |
| Saturation | `CPUUtilization` | EC2 instance CPU percentage |

A CloudWatch custom dashboard named `techstream-golden-signals` aggregates all four panels into a single view, enabling at-a-glance operational awareness.

![CloudWatch Custom Dashboards list showing the techstream-golden-signals dashboard provisioned and last updated at 2026-06-25 09:45](<docs/screenshots/Screenshot 2026-06-25 115321.png>)

---

## Part 2 — Anomaly Injection (Chaos Script)

To validate the monitoring and remediation pipeline, a chaos script fires 20 HTTP requests directly at the `/error` endpoint. Each request forces the application to return a 500 response, rapidly spiking the `ErrorCount` metric above the alarm threshold.

The effect is immediately visible across the Golden Signals dashboard: the **Errors** panel jumps to a count of 12, the **Traffic** panel records the corresponding request surge, and the **Saturation (CPU)** panel shows a brief spike as the instance handles the load burst.

![The techstream-golden-signals CloudWatch dashboard showing all four Golden Signals panels — Latency steady at ~28ms, Traffic spiking to 13 requests, Errors spiking to 12, and CPU Saturation spiking to ~5.17% — capturing the moment the chaos script fires](<docs/screenshots/Screenshot 2026-06-25 115334.png>)

---

## Part 3 — Alerting and Remediation

The `techstream-high-error-rate` CloudWatch alarm monitors the `ErrorCount` metric. When the count exceeds **5 errors per minute**, the alarm transitions to `In alarm` state, triggering the full remediation chain:

1. **CloudWatch Alarm** detects the `ErrorCount` threshold breach
2. **EventBridge Rule** listens for the alarm state change event
3. **Lambda Function** is invoked and constructs an SSM Run Command
4. **SSM Run Command** executes `systemctl restart techstream` on the EC2 instance
5. The service restarts and error rate returns to baseline — without any human action

The screenshots below capture the alarm firing in real time after the chaos script was run.

![CloudWatch Alarms console close-up showing the techstream-high-error-rate alarm in the In alarm state with actions enabled](<docs/screenshots/Screenshot 2026-06-25 114957.png>)

![CloudWatch Alarms full console view showing the techstream-high-error-rate alarm in the In alarm state, triggered at 2026-06-25 09:48:39, with the ErrorCount condition visible in the rightmost column](<docs/screenshots/Screenshot 2026-06-25 115150.png>)

---

## Part 4 — AI Analysis (DevOps Guru)

Amazon DevOps Guru was enabled with CloudFormation resource collection to provide ML-powered operational insights. DevOps Guru follows a three-stage onboarding process before it can surface anomaly findings:

**Stage 1 — Resource Discovery (2% → Complete)**

DevOps Guru scans the account to catalogue all monitored AWS resources. The first screenshot captures the discovery phase at 2% completion shortly after activation.

![Amazon DevOps Guru setup dashboard showing Step 1 (Discovering applications and resources) at 2% progress, Step 2 (Setup notifications), and Step 3 (Baselining your resources) not yet started](<docs/screenshots/Screenshot 2026-06-25 125928.png>)

**Stage 2 — Baselining (42% → Complete)**

Once discovery completes, DevOps Guru begins learning the normal operating patterns for each resource. The screenshot below shows discovery marked complete and the baselining phase underway at 42%.

![Amazon DevOps Guru setup dashboard showing Step 1 (Discovering applications and resources) marked Completed, and Step 3 (Baselining your resources) progressed to 42%](<docs/screenshots/Screenshot 2026-06-25 150726.png>)

**Stage 3 — Steady-State Dashboard**

After baselining completes, DevOps Guru reports a healthy system: 0 impacted services, 0 ongoing reactive insights, and 0 ongoing proactive insights across 5 analysed resources. Lambda, RDS, and SNS are all reported as Healthy with no active findings — confirming that the auto-remediation successfully resolved the injected anomaly before DevOps Guru needed to escalate.

![Amazon DevOps Guru main dashboard showing System health summary with 0 impacted services and 0 ongoing insights, a Resource summary of 5 resources analysed, and the System health overview listing Lambda, RDS, and SNS all as Healthy](<docs/screenshots/Screenshot 2026-06-26 120259.png>)
