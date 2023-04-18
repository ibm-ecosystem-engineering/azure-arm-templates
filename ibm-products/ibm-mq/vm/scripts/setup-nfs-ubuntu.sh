#!/bin/bash

#########################################
#
# This script setups the active virtual machine for an Multi Instance Queue Manager 
# (MIQM) configuration. This is for Ubuntu.
# Usage:
#     setup-nfs-ubuntu.sh <STORAGE_ACCOUNT> <SHARE_NAME>
#
#########################################

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

# Set defaults
if [[ -z $OUTPUT_DIR ]]; then OUTPUT_DIR="$(pwd)"; mkdir -p $OUTPUT_DIR;  fi
if [[ -z $NEW_VM ]]; then NEW_VM=true; fi
if [[ -z $SHARE_PATH ]]; then SHARE_PATH="/MQHA"; fi

# Parse cli parameters
if [[ -z $1 ]]; then
    log-output "ERROR: No storage account specified. See usage instructions."
    exit 1
else
    STORAGE_ACCOUNT=$1
fi

if [[ -z $2 ]]; then
    log-output "ERROR: No share name specified. See usage instructions."
    exit 1
else
    SHARE_NAME=$2
fi

log-output "INFO: Storage Account is set to : $STORAGE_ACCOUNT"
log-output "INFO: Share Name is set to : $SHARE_NAME"

# Delay start if a new build to let cloud-init scripts finish
if [[ $NEW_VM == true ]]; then
    log-output "INFO: Sleeping for 2 minutes to let cloud init finish"
    sleep 120
fi

# Update software repo & upgrade existing packages
log-output "INFO: Updating system"
sudo apt-get update
sudo apt-get -y dist-upgrade

# Install NFS utils
log-output "INFO: Setting up NFS tools"
sudo apt-get install -y nfs-common
if (( $? != 0 )); then
    log-output "ERROR: Unable to install nfs-common package"
    exit 1
fi

# Mount the shared NFS drive
log-output "INFO: Mounting share drive"
sudo mkdir -p $SHARE_PATH
sudo mount -t nfs ${STORAGE_ACCOUNT}.file.core.windows.net:/${STORAGE_ACCOUNT}/${SHARE_NAME} ${SHARE_PATH} -o vers=4,minorversion=1,sec=sys,noexec,nosuid,nodev
if (( $? != 0 )); then
    log-output "ERROR: Unable to mount ${STORAGE_ACCOUNT}.file.core.windows.net:/${STORAGE_ACCOUNT}/${SHARE_NAME} to ${SHARE_PATH}"
    exit 1
fi

# Add mount to fstab so it restores on reboot
log-output "INFO: Setting up fstab with share mount"
if [[ $(cat /etc/fstab | grep ${SHARE_NAME}) ]]; then
    log-output "INFO: $SHARE_NAME already configured in fstab"
else
    echo "${STORAGE_ACCOUNT}.file.core.windows.net:/${STORAGE_ACCOUNT}/${SHARE_NAME} ${SHARE_PATH} nfs vers=4,minorversion=1,sec=sys,noexec,nosuid,nodev 0 0" | sudo tee -a /etc/fstab
    if (( $? != 0 )); then
        log-output "FAIL: Unable to write to fstab. Please update manually before reboot"
    fi
fi
