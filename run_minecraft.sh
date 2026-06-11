#!/bin/bash

ENV_FILE=""

# get path
if [ -f ".gitignore/.env" ]; then
    ENV_FILE=".gitignore/.env"
elif [ -f ".env" ]; then
    ENV_FILE=".env"
elif [ -f "../.env" ]; then
    ENV_FILE="../.env"
fi

if [ -n "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "No AWS credentials file found. Create .gitignore/.env or set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN." >&2
    exit 1
fi

echo "Making EC2 instance"
source ./provisioning/provisioning_ec2.sh

echo "Starting Ansible Playbook"

python3 -m ansible playbook -i ansible/hosts.ini ansible/playbook.yml -e "ansible_host=$TARGET_IP"