#!/bin/bash
# Update and install updated packages on system

yum update -y

# Install yum-plugins-core package to provide the commands to manage your yum repos

yum -y yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2

# Set up the Docker stable repo

yum-config-manager -y \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

# Install docker 

yum install -y docker-ce

#enable docker service at boot

# Start docker

systemctl start docker

# Create docker group

groupadd docker

# add user to docker group

usermod -aG docker $USER

# Install UNMS

curl -fsSL https://raw.githubusercontent.com/Ubiquiti-App/UNMS/master/install.sh > /tmp/unms_install.sh && sudo bash /tmp/unms_install.sh

