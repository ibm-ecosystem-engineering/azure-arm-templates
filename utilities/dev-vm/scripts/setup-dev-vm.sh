#!/bin/bash

# Wait for cloud-init to finish
count=0
while [[ $(ps xua | grep cloud-init | grep -v grep) ]]; do
    echo "Waiting for cloud init to finish. Waited $count minutes. Will wait 15 mintues."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        echo "ERROR: Timeout waiting for cloud-init to finish"
        exit 1;
    fi
done

# Update machine
sudo apt update
sudo apt dist-upgrade -y

# Install jq
sudo apt install -y jq

# Get input parameters
ADMINUSER=$(cat /tmp/script-parameters.txt | grep adminuser | cut -d '=' -f2)

# Install docker
sudo apt-get install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $ADMINUSER

# Install az cli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Ansible
sudo apt update
sudo apt install -y python3 python3-pip
sudo python3 -m pip install ansible-core==2.12.3
sudo python3 -m pip install --upgrade ansible

# Install Terraform
sudo apt-get update
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
gpg --no-default-keyring \
    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    --fingerprint
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y terraform

sudo apt -y dist-upgrade