#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../infrastructure/terraform"

INSTANCE_IP=$(cd "$TERRAFORM_DIR" && terraform output -raw public_ip)
PORT="5000"
ERROR_COUNT=20

echo "Starting chaos injection..."
echo "Sending $ERROR_COUNT error requests to http://$INSTANCE_IP:$PORT/error"

for i in $(seq 1 $ERROR_COUNT); do
  curl -s "http://$INSTANCE_IP:$PORT/error" > /dev/null
  echo "Error request $i sent"
  sleep 1
done

echo "Chaos injection complete. Check CloudWatch alarm in ~1 minute."
