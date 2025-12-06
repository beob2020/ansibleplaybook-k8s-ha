# RKE2 Production Deployment with Ansible

This repository contains production-ready Ansible playbooks for deploying RKE2 (Rancher Kubernetes Engine 2) clusters.

## 📋 Prerequisites

### System Requirements
- **Master Nodes**: Minimum 4GB RAM, 2 vCPUs, 50GB disk
- **Worker Nodes**: Minimum 4GB RAM, 2 vCPUs, 50GB disk
- **OS**: Ubuntu 20.04/22.04 LTS or RHEL/CentOS 8+
- **Network**: All nodes must be reachable from the Ansible control node

### Control Node Requirements
- Ansible 2.12 or higher
- Python 3.8+
- jq (for script operations)
- SSH key-based authentication to all nodes

## 🚀 Quick Start

### 1. Install Prerequisites

```bash
# Install Ansible and dependencies
sudo apt update
sudo apt install -y python3-pip ansible jq

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure Inventory

Edit `inventory.yml` to match your infrastructure:

```yaml
all:
  vars:
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    rke2_version: "v1.28.3+rke2r2"
    
  hosts:
    main:
      ansible_host: 192.168.178.101
      ansible_user: main
      hostname: main
```

### 3. Secure Your Passwords

Use ansible-vault to encrypt sensitive data:

```bash
# Encrypt the become password
ansible-vault encrypt_string 'your_sudo_password' --name 'ansible_become_password'
```

### 4. Deploy the Cluster

```bash
# Full deployment
./deploy.sh deploy

# Or step by step:
./deploy.sh check      # Check prerequisites
./deploy.sh test       # Test connectivity
./deploy.sh master     # Deploy master node
./deploy.sh workers    # Deploy worker nodes
./deploy.sh validate   # Validate deployment
```

## 📁 Project Structure

```
.
├── ansible.cfg              # Ansible configuration
├── inventory.yml            # Inventory file with hosts
├── deploy-rke2.yml         # Main playbook
├── requirements.yml        # Ansible collection requirements
├── deploy.sh              # Deployment script
├── templates/
│   └── rke2-server-config.j2  # RKE2 server configuration template
└── logs/                  # Deployment logs (created automatically)
```

## 🎯 Features

### Security Features
- CIS 1.23 benchmark compliance
- Secrets encryption at rest
- Node token authentication
- Firewall rules configuration
- SELinux support (optional)

### High Availability
- Multi-master support (add more masters in inventory)
- Automatic etcd snapshots (every 12 hours)
- Systemd service hardening with auto-restart

### Network Features
- Calico CNI by default
- Configurable cluster and service CIDRs
- Node IP configuration
- Support for external IPs

### Storage Options
- Optional Longhorn deployment
- Support for multiple storage backends
- iSCSI and NFS client pre-configured

## 🛠 Advanced Configuration

### Custom RKE2 Version

Edit `inventory.yml`:
```yaml
all:
  vars:
    rke2_version: "v1.29.0+rke2r1"
    rke2_channel: stable
```

### Enable Longhorn Storage

```bash
./deploy.sh longhorn
```

### Custom Network Configuration

Edit `inventory.yml`:
```yaml
all:
  vars:
    cluster_cidr: "10.42.0.0/16"
    service_cidr: "10.43.0.0/16"
```

### Add Node Labels

In `inventory.yml`:
```yaml
hosts:
  worker1:
    node_labels:
      - "workload=general"
      - "storage=ssd"
```

## 🔧 Troubleshooting

### Check Logs

```bash
# Deployment logs
tail -f logs/deployment_*.log

# RKE2 server logs
sudo journalctl -u rke2-server -f

# RKE2 agent logs
sudo journalctl -u rke2-agent -f
```

### Common Issues

1. **Connection refused on port 6443**
   ```bash
   # Check if RKE2 server is running
   sudo systemctl status rke2-server
   ```

2. **Worker node won't join**
   ```bash
   # Check token on master
   sudo cat /var/lib/rancher/rke2/server/node-token
   
   # Verify config on worker
   sudo cat /etc/rancher/rke2/config.yaml
   ```

3. **DNS issues**
   ```bash
   # Check CoreDNS pods
   kubectl get pods -n kube-system | grep coredns
   ```

## 🔐 Security Considerations

1. **Encrypt sensitive data**: Always use ansible-vault for passwords
2. **Network segmentation**: Use private networks for cluster communication
3. **Regular updates**: Keep RKE2 and system packages updated
4. **RBAC**: Implement proper RBAC policies after deployment
5. **Audit logging**: Enabled by default, check `/var/lib/rancher/rke2/server/logs/`

## 📊 Monitoring & Maintenance

### Backup etcd

```bash
# Manual backup
sudo /var/lib/rancher/rke2/bin/rke2 etcd-snapshot save --name manual-backup

# List backups
sudo ls -la /var/lib/rancher/rke2/server/db/snapshots/
```

### Upgrade Cluster

1. Update version in inventory.yml
2. Run playbook with upgrade tag:
   ```bash
   ansible-playbook -i inventory.yml deploy-rke2.yml --tags upgrade
   ```

## 🧹 Cleanup

To completely remove RKE2:

```bash
./deploy.sh cleanup
```

⚠️ **WARNING**: This will destroy the entire cluster and all data!

## 📝 Post-Deployment Steps

1. **Get kubeconfig**:
   ```bash
   export KUBECONFIG=./kubeconfig.yaml
   kubectl get nodes
   ```

2. **Install Ingress Controller**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
   ```

3. **Install Metrics Server**:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

4. **Setup Monitoring** (Prometheus + Grafana):
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install monitoring prometheus-community/kube-prometheus-stack
   ```

## 📖 Additional Resources

- [RKE2 Documentation](https://docs.rke2.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Calico Documentation](https://docs.projectcalico.org/)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## ⚖️ License

MIT License - feel free to use in your projects.

## 🚨 Production Checklist

Before going to production, ensure:

- [ ] All nodes meet minimum requirements
- [ ] Network connectivity between all nodes
- [ ] DNS resolution working properly
- [ ] Time synchronized across all nodes (NTP)
- [ ] Firewall rules configured
- [ ] Backup strategy in place
- [ ] Monitoring configured
- [ ] Load balancer for HA masters (if multiple masters)
- [ ] Storage solution deployed
- [ ] RBAC policies configured
- [ ] Network policies defined
- [ ] Resource quotas set
- [ ] Audit logging enabled
- [ ] Regular update schedule planned
