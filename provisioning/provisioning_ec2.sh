#!/bin/bash

handle_error() {
    echo "Error: $1" >&2
    exit 1
}


# Function to check if a resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"

    case "$resource_type" in
        "security-group")
            aws ec2 describe-security-groups --filters "Name=group-name,Values=$resource_id" --query "SecurityGroups[*].GroupId" --output text | grep -q "sg-"            ;;
        "key-pair")
            aws ec2 describe-key-pairs --key-names "$resource_id" &>/dev/null
            ;;
    esac
}

find_running_instance() {
    if ! ssh-keygen -y -f "$PWD/MinecraftKey.pem" >/dev/null 2>&1; then
        return 1
    fi

    aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=Minecraft Server" \
        --query 'Reservations[].Instances[0].InstanceId' \
        --output text 2>/dev/null
}


# Get the default VPC ID first
echo "Getting default VPC..."
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)
    
# Get available subnets in the default VPC
echo "Getting available subnets in the default VPC..."
SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=default-for-az,Values=true" \
    --query "Subnets[0:3].SubnetId" \
    --output text)

# Convert space-separated subnet IDs to an array
read -r -a SUBNET_ARRAY <<< "$SUBNETS"

if [ ${#SUBNET_ARRAY[@]} -lt 3 ]; then
    handle_error "Not enough subnets available in the default VPC. Need at least 3 subnets, found ${#SUBNET_ARRAY[@]}."
fi

echo "Checking if Security Group exists"
if resource_exists "security-group" "minecraft-security-group"; then
    echo "Security Group already exists"
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=minecraft-security-group" "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        --query "SecurityGroups[0].GroupId" \
        --output text)
else
    echo "Creating Security Group"
    SG_ID=$(aws ec2 create-security-group \
        --group-name minecraft-security-group \
        --description "My security group" \
        --vpc-id $DEFAULT_VPC_ID \
        --query "GroupId" \
        --output text)
    echo "Created Security Group: $SG_ID"
fi

# Allow SSH access to client from your IP only
echo "Getting your public IP address"
MY_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null)
if [ -z "$MY_IP" ]; then
    echo "Warning: Could not determine your IP address. Using 0.0.0.0/0 (not recommended for production)"
    MY_IP="0.0.0.0/0"
else
    MY_IP="$MY_IP/32"
    echo "Your IP address: $MY_IP"
fi
echo "Adding SSH ingress rule to client security group"
SSH_RULE_RESPONSE=$(aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_IP" 2>&1)
# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Warning: Failed to add SSH ingress rule: $SSH_RULE_RESPONSE"
    echo "You may need to manually add SSH access to security group $SG_ID"
fi
echo "SSH ingress rule added"
TCP_RULE_RESPONSE=$(aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 25565 \
    --cidr 0.0.0.0/0)
# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Warning: Failed to add SSH ingress rule: $TCP_RULE_RESPONSE"
    echo "You may need to manually add SSH access to security group $SG_ID"
fi

# Get a Ubuntu AMI that works in AWS Academy learner labs
echo "Getting latest Ubuntu AMI ID"
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*" "Name=state,Values=available" "Name=architecture,Values=x86_64" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text 2>/dev/null)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    handle_error "Failed to get Ubuntu AMI ID"
fi
echo "Using AMI ID: $AMI_ID"

echo "Checking key pair"

EXISTING_INSTANCE_ID=$(find_running_instance)
if [ -n "$EXISTING_INSTANCE_ID" ]; then
    echo "Found existing running learner-lab instance: $EXISTING_INSTANCE_ID"
    INSTANCE_ID="$EXISTING_INSTANCE_ID"
else
    echo "Creating EC2 Instance"
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t3.micro \
        --security-group-ids "$SG_ID" \
        --subnet-id "${SUBNET_ARRAY[0]}" \
        --key-name "$KEY_NAME" \
        --query "Instances[0].InstanceId" \
        --output text)

    echo "EC2 instance launched successfully. ID: $INSTANCE_ID"
fi
echo "Waiting for instance to be running..."

wait_for_instance_running() {
    local instance_id="$1"
    local attempts=0
    local max_attempts=60

    echo "Waiting for instance $instance_id to enter running state..."

    while [ "$attempts" -lt "$max_attempts" ]; do
        local state
        local reason

        state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || true)

        reason=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].StateReason.Message' \
            --output text 2>/dev/null || true)

        case "$state" in
            running)
                echo "Instance $instance_id is running."
                return 0
                ;;
            shutting-down|stopping|stopped)
                echo "Instance $instance_id entered transitional state: $state"
                if [ -n "$reason" ] && [ "$reason" != "None" ]; then
                    echo "Reason: $reason"
                fi
                # Some lab environments briefly report a shutdown transition; keep polling.
                ;;
            terminated)
                echo "Instance $instance_id is terminated: $reason"
                return 1
                ;;
            pending)
                echo "Instance $instance_id is still pending..."
                ;;
            "")
                echo "Instance $instance_id not found yet; retrying..."
                ;;
            *)
                echo "Instance $instance_id is in unexpected state: $state"
                ;;
        esac

        attempts=$((attempts + 1))
        sleep 15
    done

    echo "Timed out waiting for instance $instance_id to become running."
    return 1
}

if ! wait_for_instance_running "$INSTANCE_ID"; then
    handle_error "Instance failed to reach running state"
fi

# Wait a bit more for the instance to initialize
echo "Waiting 30 seconds for initialization..."
sleep 30

echo "Getting public IP address"
TARGET_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Retrieved target IP: $TARGET_IP"
