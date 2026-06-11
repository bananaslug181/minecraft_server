# minecraft_server Setup Guide

# Backround: I am going to walk through the steps on how to host a Minecraft server using a bash script to launch an EC2 Instance, and Ansible. We will do it by creating a script to provision the EC2 instance, creating a YML playbook to run Ansible, and then making one giant script to run both the playbook and the EC2 script altogether.

# Requirements:
1. Install AWS specific to your Device ( OS specific tutorial: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. Install Ansible: type 'brew install ansible'

# List of Commands to Run:
1. Run `aws configure` and follow the prompts, or place credentials in `.gitignore/.env`.
2. Make sure `.gitignore/.env` contains valid `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` values.
3. Run `source .gitignore/.env` (or `set -a && source .gitignore/.env && set +a`) and then `aws sts get-caller-identity` to confirm the credentials work.
4. Run `chmod +x run_minecraft.sh` to give permissions.
5. Run `./run_minecraft.sh` from the project root.

# How to Connect Once Running:
   
# Sources:
## for run_minecraft.sh: 
Amazon Web Services, "Getting started with Amazon MSK - Amazon Elastic Compute Cloud," AWS Documentation, 2026. [Online]. Available: https://docs.aws.amazon.com/ec2/latest/devguide/example_ec2_GettingStarted_057_section.html
## playbook.yml:
T. Hummel, "Minecraft Server Setup," Tom Hummel, May 26, 2024. [Online]. Available: https://tomhummel.com/posts/minecraft-server-setup/ (accessed Jun. 10, 2026).
