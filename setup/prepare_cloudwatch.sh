#!/usr/bin/env bash
source init.sh

# Setup cloudwatch file monitoring on EC2 instances using cloudwatch logs
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AgentReference.html

REMOTE=$(cat <<EOF
echo Creating CloudWatch config in /root/awslogs.conf
echo """
[general]
state_file = /var/awslogs/state/agent-state
use_gzip_http_content_encoding = true

[syslog]
datetime_format = %Y-%m-%d %H:%M:%S
file = /var/log/syslog
buffer_duration = 5000
log_stream_name = {instance_id}-{ip_address}-syslog
initial_position = start_of_file
log_group_name = $TAG-futuswarm-syslog
""" > /root/awslogs.conf

if [[ -f "/var/awslogs/bin/aws" && -f "/var/awslogs/bin/awslogs-agent-launcher.sh" ]]; then
    echo "Cloudwatch logs agent already installed"
else
echo Downloading cloudwatch logs setup agent
cd /root
wget https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py

echo Running non-interactive awslogs-agent-setup
python ./awslogs-agent-setup.py --region=$AWS_REGION --non-interactive --configfile=/root/awslogs.conf
fi

pip install awscli-cwlogs==1.4.4
aws configure set plugins.cwlogs cwlogs||true

EOF
)
run_sudo $HOST "$REMOTE"

#IS_INSTALLED=$(run_sudo $HOST "is_pip_installed awscli")

# check if exists, re-install if doesnt
#/var/awslogs/bin/awslogs-agent-launcher.sh

synchronize awslogs.service /lib/systemd/system/ $HOST

REMOTE=$(cat <<EOF
systemctl daemon-reload
systemctl enable awslogs.service||true
systemctl start awslogs.service||true
EOF
)
run_sudo $HOST "$REMOTE"
