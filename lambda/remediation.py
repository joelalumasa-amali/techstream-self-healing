import boto3
import os
import json

def handler(event, context):
    instance_id = os.environ.get('INSTANCE_ID')
    region = os.environ.get('REGION', 'us-east-1')
    
    print(f"Remediation triggered for instance {instance_id}")
    print(f"Event: {json.dumps(event)}")
    
    ssm = boto3.client('ssm', region_name=region)
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={
            'commands': [
                'echo "Self-healing triggered at $(date)"',
                'systemctl restart techstream',
                'echo "Service restarted successfully"',
                'systemctl status techstream'
            ]
        }
    )
    
    command_id = response['Command']['CommandId']
    print(f"SSM command sent: {command_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Remediation executed',
            'command_id': command_id,
            'instance_id': instance_id
        })
    }
