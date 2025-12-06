#!/bin/bash

# RKE2 Cluster Deployment Script
# This script manages the deployment of RKE2 cluster using Ansible

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PLAYBOOK="deploy-rke2.yml"
INVENTORY="inventory.yml"
LOG_DIR="logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/deployment_${TIMESTAMP}.log"

# Functions
print_header() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}============================================${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible first."
        echo "To install Ansible on Ubuntu/Debian:"
        echo "  sudo apt update && sudo apt install -y ansible"
        echo "To install Ansible on RHEL/CentOS:"
        echo "  sudo yum install -y ansible"
        exit 1
    fi
    
    # Check if ansible-galaxy is installed
    if ! command -v ansible-galaxy &> /dev/null; then
        print_error "ansible-galaxy is not installed."
        exit 1
    fi
    
    # Check Python version - using awk for compatibility
    if command -v python3 &> /dev/null; then
        python_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
        print_info "Python version: $python_version"
    else
        print_error "Python3 is not installed"
        exit 1
    fi
    
    # Check if jq is installed (optional but recommended)
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Some features may not work."
        print_info "To install: sudo apt install -y jq"
    fi
    
    # Check inventory file
    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file $INVENTORY not found!"
        exit 1
    fi
    
    # Check playbook file
    if [ ! -f "$PLAYBOOK" ]; then
        print_error "Playbook file $PLAYBOOK not found!"
        exit 1
    fi
    
    # Check template directory
    if [ ! -d "templates" ]; then
        print_warning "Templates directory not found. Creating it..."
        mkdir -p templates
    fi
    
    print_info "All prerequisites checked successfully"
}

install_requirements() {
    print_header "Installing Ansible Requirements"
    
    if [ -f "requirements.yml" ]; then
        print_info "Installing required Ansible collections..."
        ansible-galaxy collection install -r requirements.yml --force
        
        if [ $? -eq 0 ]; then
            print_info "Collections installed successfully"
        else
            print_warning "Some collections may have failed to install"
        fi
    else
        print_warning "requirements.yml not found, skipping collection installation"
    fi
}

create_log_directory() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        print_info "Created log directory: $LOG_DIR"
    fi
}

test_connectivity() {
    print_header "Testing Connectivity to All Nodes"
    
    # Create log file if it doesn't exist
    create_log_directory
    
    print_info "Pinging all nodes..."
    ansible all -i "$INVENTORY" -m ping 2>&1 | tee -a "$LOG_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_info "Successfully connected to all nodes"
    else
        print_error "Failed to connect to some nodes. Please check:"
        print_error "  1. SSH keys are properly configured"
        print_error "  2. Inventory file has correct IPs and usernames"
        print_error "  3. Nodes are reachable over the network"
        print_error "  4. SSH service is running on target nodes"
        exit 1
    fi
}

deploy_cluster() {
    print_header "Deploying RKE2 Cluster"
    
    case "$1" in
        full)
            print_info "Running full deployment..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        master)
            print_info "Deploying master nodes only..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "master" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        workers)
            print_info "Deploying worker nodes only..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "workers" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        preflight)
            print_info "Running preflight checks only..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "preflight" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        validation)
            print_info "Running validation only..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "validation" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        longhorn)
            print_info "Deploying Longhorn storage..."
            ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "longhorn" -v 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            print_error "Invalid deployment type. Use: full, master, workers, preflight, validation, or longhorn"
            exit 1
            ;;
    esac
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_info "Deployment completed successfully!"
        print_info "Log file: $LOG_FILE"
    else
        print_error "Deployment failed! Check the log file: $LOG_FILE"
        exit 1
    fi
}

validate_cluster() {
    print_header "Validating Cluster"
    
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --tags "validation" 2>&1 | tee -a "$LOG_FILE"
}

fetch_kubeconfig() {
    print_header "Fetching Kubeconfig"
    
    # Get master host information
    if command -v jq &> /dev/null; then
        # Use jq if available
        master_host=$(ansible-inventory -i "$INVENTORY" --list | jq -r '.masters.hosts[0]')
        master_ip=$(ansible-inventory -i "$INVENTORY" --host "$master_host" | jq -r '.ansible_host')
    else
        # Fallback method without jq
        master_host="main"  # Using the default from your inventory
        master_ip=$(ansible -i "$INVENTORY" "$master_host" -m debug -a "var=ansible_host" | grep ansible_host | cut -d'"' -f4)
    fi
    
    print_info "Fetching kubeconfig from $master_host..."
    
    ansible "$master_host" -i "$INVENTORY" -m fetch \
        -a "src=/etc/rancher/rke2/rke2.yaml dest=./kubeconfig.yaml flat=yes" 2>&1 | tee -a "$LOG_FILE"
    
    if [ -f "kubeconfig.yaml" ]; then
        # Update the server address
        if command -v sed &> /dev/null; then
            sed -i.bak "s/127.0.0.1/${master_ip:-192.168.178.101}/g" kubeconfig.yaml
            rm -f kubeconfig.yaml.bak
        fi
        print_info "Kubeconfig saved to: kubeconfig.yaml"
        print_info "To use it: export KUBECONFIG=$(pwd)/kubeconfig.yaml"
    else
        print_warning "Failed to fetch kubeconfig"
    fi
}

cleanup() {
    print_header "Cleaning Up Cluster (DESTRUCTIVE)"
    
    read -p "Are you sure you want to remove RKE2 from all nodes? (yes/no): " confirm
    
    if [ "$confirm" == "yes" ]; then
        ansible all -i "$INVENTORY" -b -m shell -a "
            systemctl stop rke2-server || true;
            systemctl stop rke2-agent || true;
            systemctl disable rke2-server || true;
            systemctl disable rke2-agent || true;
            /usr/local/bin/rke2-uninstall.sh || true;
            /usr/local/bin/rke2-agent-uninstall.sh || true;
            rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /etc/kubernetes;
            rm -f /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/helm;
        " 2>&1 | tee -a "$LOG_FILE"
        
        print_info "Cluster cleanup completed"
    else
        print_info "Cleanup cancelled"
    fi
}

show_usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
  check       - Check prerequisites only
  test        - Test connectivity to all nodes
  deploy      - Full deployment (masters and workers)
  master      - Deploy master nodes only
  workers     - Deploy worker nodes only
  preflight   - Run preflight checks only
  validate    - Validate cluster deployment
  longhorn    - Deploy Longhorn storage
  kubeconfig  - Fetch kubeconfig file
  cleanup     - Remove RKE2 from all nodes (DESTRUCTIVE)
  help        - Show this help message

Examples:
  $0 check      # Check prerequisites
  $0 test       # Test connectivity
  $0 deploy     # Full cluster deployment
  $0 validate   # Validate cluster after deployment

For step-by-step deployment:
  1. $0 check      # Verify prerequisites
  2. $0 test       # Test connectivity
  3. $0 preflight  # Run preflight checks
  4. $0 master     # Deploy master
  5. $0 workers    # Deploy workers
  6. $0 validate   # Validate deployment
  7. $0 kubeconfig # Get kubeconfig
EOF
}

# Main script
main() {
    case "${1:-help}" in
        check)
            check_prerequisites
            install_requirements
            ;;
        test)
            check_prerequisites
            test_connectivity
            ;;
        deploy)
            check_prerequisites
            install_requirements
            create_log_directory
            test_connectivity
            deploy_cluster "full"
            validate_cluster
            fetch_kubeconfig
            ;;
        master)
            check_prerequisites
            create_log_directory
            deploy_cluster "master"
            ;;
        workers)
            check_prerequisites
            create_log_directory
            deploy_cluster "workers"
            ;;
        preflight)
            check_prerequisites
            create_log_directory
            deploy_cluster "preflight"
            ;;
        validate)
            create_log_directory
            validate_cluster
            ;;
        longhorn)
            check_prerequisites
            create_log_directory
            deploy_cluster "longhorn"
            ;;
        kubeconfig)
            create_log_directory
            fetch_kubeconfig
            ;;
        cleanup)
            create_log_directory
            cleanup
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Invalid command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"