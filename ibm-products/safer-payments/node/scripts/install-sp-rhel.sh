#!/bin/bash

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/tmp"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

log-output "INFO: Script started"

# Exit if no parameters provided
if [[ -z $1 ]]; then
    log-output "ERROR: Missing argument"
    log-output "INFO: Usage: $0 TYPE"
    log-output "INFO:    where "
    log-output "INFO:         TYPE is the node type to configure - primary, ha, dr or standby"
    exit 1
fi

TYPE=$1
log-output "INFO: Configuring node as $TYPE"

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

# Updating OS
sudo yum -y update

# Download safer payments binary

# Run safer payments installation
# $LICENSE_ACCEPTED$=true
# sh ./SaferPayments.bin -i silent

# Run safer payments postrequisites
# cp -R /installationPath/factory_reset/* /instancePath 
# chown -R SPUser:SPUserGroup /instancePath

# Shutdown node if standby
if [[ $TYPE = "standby" ]]; then
    log-output "INFO: Shutting down"
    sudo shutdown -h 0
fi