#!/bin/bash
set -euo pipefail

# =============================
# Debian 13 Auto-Start Script
# =============================

# Configuration
VM_NAME="debian13"
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
HOSTNAME="debian13"
USERNAME="user"
PASSWORD="password"
DISK_SIZE="20G"
MEMORY="2048"
CPUS="2"
SSH_PORT="2222"

# Directories
VM_DIR="$HOME/.vms"
IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
SEED_FILE="$VM_DIR/$VM_NAME-seed.img"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
}

# Check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Dependencies should be available via dev.nix packages"
        exit 1
    fi
}

# Create VM directory
mkdir -p "$VM_DIR"

print_status "INFO" "Starting Debian 13 VM setup..."

# Check dependencies
check_dependencies

# Download Debian 13 image if not exists
if [[ ! -f "$IMG_FILE" ]]; then
    print_status "INFO" "Downloading Debian 13 image..."
    wget -O "$IMG_FILE" "$DEBIAN_IMAGE_URL"
    print_status "SUCCESS" "Image downloaded"
    
    print_status "INFO" "Resizing disk to $DISK_SIZE..."
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"
else
    print_status "INFO" "Using existing image: $IMG_FILE"
fi

# Create cloud-init configuration
print_status "INFO" "Creating cloud-init configuration..."

cat > /tmp/user-data <<'USERDATA'
#cloud-config
users:
  - name: user
    gecos: Default User
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: $6$rounds=4096$saltsalt$IxDD3jeSOb5eB1CX5LBsqZFVkJdido3OUILO5Ifz5iwMuTS4XMS130MTSuDDl3aCI6WouIL9AjRbLCelDCy.g.
    ssh_authorized_keys: []

ssh_pwauth: true
disable_root: false

package_update: true
package_upgrade: false

runcmd:
  - echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
  - echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
  - systemctl restart ssh

final_message: "Debian 13 VM is ready! SSH: ssh -p 2222 user@localhost"
USERDATA

cat > /tmp/meta-data <<METADATA
instance-id: $VM_NAME
local-hostname: $HOSTNAME
METADATA

# Create seed image
print_status "INFO" "Creating cloud-init seed image..."
cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data

# Cleanup temp files
rm -f /tmp/user-data /tmp/meta-data

# Start VM
print_status "INFO" "Starting Debian 13 VM..."
print_status "INFO" "VM Name: $VM_NAME"
print_status "INFO" "SSH Port: $SSH_PORT"
print_status "INFO" "Username: $USERNAME"
print_status "INFO" "Password: $PASSWORD"
print_status "INFO" "Memory: ${MEMORY}M"
print_status "INFO" "CPUs: $CPUS"

# Start QEMU in background
nohup qemu-system-x86_64 \
    -name "$VM_NAME" \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp "$CPUS" \
    -m "$MEMORY" \
    -drive file="$IMG_FILE",format=qcow2,if=virtio \
    -drive file="$SEED_FILE",format=raw,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic \
    -serial mon:stdio \
    > "$VM_DIR/$VM_NAME.log" 2>&1 &

VM_PID=$!
echo "$VM_PID" > "$VM_DIR/$VM_NAME.pid"

print_status "SUCCESS" "VM started with PID: $VM_PID"
print_status "INFO" ""
print_status "INFO" "Connect to VM:"
print_status "INFO" "  ssh -p $SSH_PORT $USERNAME@localhost"
print_status "INFO" "  Password: $PASSWORD"
print_status "INFO" ""
print_status "INFO" "VM logs: $VM_DIR/$VM_NAME.log"
print_status "INFO" "To stop VM: kill \$(cat $VM_DIR/$VM_NAME.pid)"
