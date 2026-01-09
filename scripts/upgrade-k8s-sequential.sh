#!/bin/bash
set -e

# ==============================================================================
# Kubernetes Sequential Upgrade Script (v1.31 -> v1.35)
# ==============================================================================
# Usage: sudo ./upgrade-k8s-sequential.sh
# This script upgrades a single-node kubeadm cluster step-by-step.
# ==============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Upgrade Path
VERSIONS=("v1.32" "v1.33" "v1.34" "v1.35")

echo -e "${GREEN}Starting Kubernetes Sequential Upgrade${NC}"
echo -e "Current Target Path: ${YELLOW}${VERSIONS[*]}${NC}"
echo "--------------------------------------------------------"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo)${NC}"
  exit 1
fi

# Ensure Kubectl can talk to the cluster
export KUBECONFIG=/etc/kubernetes/admin.conf
if [ ! -f "$KUBECONFIG" ]; then
    echo -e "${RED}Error: $KUBECONFIG not found. Is the cluster running?${NC}"
    exit 1
fi


# Function to perform upgrade for a specific version
upgrade_to_version() {
    local VER=$1
    echo ""
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN} Upgrading to ${VER} ...${NC}"
    echo -e "${GREEN}==============================================${NC}"
    
    # 1. Update Apt Repository
    echo -e "${YELLOW}[1/5] Updating Apt Repository for ${VER}...${NC}"
    mkdir -p /etc/apt/keyrings
    # Overwrite keyring and list for the new version
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${VER}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${VER}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

    apt-get update

    # 2. Upgrade Kubeadm
    echo -e "${YELLOW}[2/5] Upgrading kubeadm...${NC}"
    apt-mark unhold kubeadm
    apt-get install -y "kubeadm" 
    apt-mark hold kubeadm
    
    # Verify kubeadm version
    KUBEADM_VER=$(kubeadm version -o short)
    echo -e "Kubeadm upgraded to: ${KUBEADM_VER}"

    # 3. Apply Cluster Upgrade
    echo -e "${YELLOW}[3/5] Applying Cluster Upgrade...${NC}"
    # Use the version reported by kubeadm to apply
    kubeadm upgrade apply "${KUBEADM_VER}" -y

    # 4. Upgrade Kubelet and Kubectl
    echo -e "${YELLOW}[4/5] Upgrading kubelet and kubectl...${NC}"
    # Drain node (optional for single node, but good practice script-wise, usually skipped for single-node if acceptable downtime)
    # kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data
    
    apt-mark unhold kubelet kubectl
    apt-get install -y "kubelet" "kubectl"
    apt-mark hold kubelet kubectl

    # 5. Restart Kubelet
    echo -e "${YELLOW}[5/5] Restarting kubelet...${NC}"
    systemctl daemon-reload
    systemctl restart kubelet
    
    # Wait for node to be ready?
    echo "Waiting 10s for service stabilization..."
    sleep 10
    
    # kubectl uncordon $(hostname)
    
    echo -e "${GREEN}✅ Upgrade to ${VER} Complete!${NC}"
    kubectl get nodes -o wide
}

# Main Loop
for VERSION in "${VERSIONS[@]}"; do
    CURRENT_MAJOR_MINOR=$(kubectl get nodes $(hostname) -o jsonpath='{.status.nodeInfo.kubeletVersion}' | cut -d. -f1-2)
    
    # Skip if current version is already greater than or equal to the target version
    # e.g. if CURRENT is v1.32 and VERSION is v1.32, skip it.
    if [[ "$CURRENT_MAJOR_MINOR" == "$VERSION" ]] || [[ "$CURRENT_MAJOR_MINOR" > "$VERSION" ]]; then
        echo -e "${YELLOW}Skipping ${VERSION} (Already at ${CURRENT_MAJOR_MINOR})${NC}"
        continue
    fi

    echo ""
    read -p "Ready to upgrade to ${VERSION}? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Upgrade aborted by user at version ${VERSION}.${NC}"
        exit 1
    fi
    
    upgrade_to_version "$VERSION"
done

echo ""
echo -e "${GREEN}🎉 All upgrades completed successfully! You are now on v1.35.${NC}"
