data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP and SSH"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-USERDATA
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip
    pip3 install flask boto3

    cat > /home/ec2-user/app.py << 'APPEOF'
    import time
    import random
    from flask import Flask, jsonify
    import boto3

    app = Flask(__name__)
    cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')

    def put_metric(name, value, unit='Count'):
        cloudwatch.put_metric_data(
            Namespace='TechStream',
            MetricData=[{
                'MetricName': name,
                'Value': value,
                'Unit': unit
            }]
        )

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
        import os
        os.system('stress-ng --cpu 1 --timeout 10s &')
        return jsonify({'chaos': 'activated'}), 500

    @app.route('/health')
    def health():
        return jsonify({'healthy': True})

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5000)
    APPEOF

    pip3 install stress-ng 2>/dev/null || yum install -y stress-ng

    cat > /etc/systemd/system/techstream.service << 'SVCEOF'
    [Unit]
    Description=TechStream Web Server
    After=network.target

    [Service]
    User=ec2-user
    WorkingDirectory=/home/ec2-user
    ExecStart=/usr/bin/python3 /home/ec2-user/app.py
    Restart=always
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    systemctl daemon-reload
    systemctl enable techstream
    systemctl start techstream
  USERDATA

  tags = {
    Name = "${var.project_name}-web-server"
  }
}

output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}
