import os
import time
from flask import Flask, jsonify
import boto3

app = Flask(__name__)


def get_cloudwatch():
    return boto3.client(
        'cloudwatch',
        region_name=os.environ.get('AWS_REGION', 'us-east-1')
    )


def put_metric(name, value, unit='Count'):
    try:
        get_cloudwatch().put_metric_data(
            Namespace='TechStream',
            MetricData=[{
                'MetricName': name,
                'Value': value,
                'Unit': unit
            }]
        )
    except Exception:
        pass


@app.route('/')
def home():
    start = time.time()
    put_metric('RequestCount', 1)
    latency = (time.time() - start) * 1000
    put_metric('Latency', latency, 'Milliseconds')
    return jsonify({'status': 'ok', 'service': 'TechStream'})


@app.route('/error')
def error():
    put_metric('ErrorCount', 1)
    put_metric('RequestCount', 1)
    return jsonify({'error': 'simulated error'}), 500


@app.route('/chaos')
def chaos():
    put_metric('ErrorCount', 1)
    put_metric('RequestCount', 1)
    os.system('stress-ng --cpu 1 --timeout 10s &')
    return jsonify({'chaos': 'activated'}), 500


@app.route('/health')
def health():
    return jsonify({'healthy': True})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
