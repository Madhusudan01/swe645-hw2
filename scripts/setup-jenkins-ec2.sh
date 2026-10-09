#!/bin/bash
# Author: Madhusudan Kharote - SWE645 Homework 2
# Purpose: One-time setup for an Ubuntu 24.04 EC2 instance that installs Jenkins,
# Docker, kubectl, and AWS CLI v2 so Jenkins can build and deploy to EKS.
set -e

echo "== Java + Jenkins =="
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre unzip curl wget
sudo mkdir -p /etc/apt/keyrings
# If apt reports a key error, copy the current key commands from https://pkg.jenkins.io/debian-stable/
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins

echo "== Docker =="
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins      # lets the pipeline run docker without sudo

echo "== kubectl =="
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

echo "== AWS CLI v2 =="
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

sudo systemctl restart jenkins
echo
echo "Done. Open http://<EC2-PUBLIC-IP>:8080 - initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
