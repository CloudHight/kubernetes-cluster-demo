#!/bin/bash

# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure container runtime (containerd)
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Install containerd
apt install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components (version 1.29)
apt update
apt install -y kubelet=1.29.0-1.1 kubeadm=1.29.0-1.1 kubectl=1.29.0-1.1
apt-mark hold kubelet kubeadm kubectl

# Initialize Kubernetes cluster
kubeadm init --pod-network-cidr=10.244.0.0/16 --kubernetes-version v1.29.0

# Set up kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Install Flannel network plugin
sudo -u ubuntu kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Create join command script
sudo -u ubuntu kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install
sudo ln -svf /usr/local/bin/aws /usr/bin/aws

# save join command to s3 bucket
JOIN_COMMAND=$(cat /home/ubuntu/join-command.sh)
aws s3 cp /home/ubuntu/join-command.sh s3://k8sjoin-bucket2 --region eu-west-1

# Install additional tools
sudo -u ubuntu curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo -u ubuntu install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
