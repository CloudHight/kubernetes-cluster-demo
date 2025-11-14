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

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install
sudo ln -svf /usr/local/bin/aws /usr/bin/aws

# Retrieve join command from s3 bucket and execute it
aws s3 cp s3://k8sjoin-bucket2/join-command.sh /home/ubuntu/join-command.sh --region eu-west-1
chmod +x /home/ubuntu/join-command.sh

# Execute the join command as root user
bash /home/ubuntu/join-command.sh
