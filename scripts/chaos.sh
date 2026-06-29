#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../infrastructure/terraform"

INSTANCE_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw instance_id)
REGION="us-east-1"
PORT="5000"
ERROR_COUNT=20

echo "Starting chaos injection via SSM Run Command..."
echo "Target instance: $INSTANCE_ID"

# Use cli-input-json so the loop command survives shell quoting intact.
# \$ in the unquoted heredoc becomes a literal $ in the JSON, which is
# then expanded by bash on the remote instance (not locally).
COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text \
  --cli-input-json "$(cat <<-ENDJSON
  {
    "InstanceIds": ["$INSTANCE_ID"],
    "DocumentName": "AWS-RunShellScript",
    "Parameters": {
      "commands": [
        "for i in \$(seq 1 $ERROR_COUNT); do curl -s http://127.0.0.1:$PORT/error >/dev/null; echo Error request \$i sent; sleep 1; done"
      ]
    }
  }
ENDJSON
  )")

echo "SSM command sent: $COMMAND_ID"
echo "Waiting for execution to complete..."

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" || true

echo ""
echo "--- Output from instance ---"
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

echo "Chaos injection complete. Check CloudWatch alarm in ~1 minute."
