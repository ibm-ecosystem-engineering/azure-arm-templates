#!/bin/bash
##############
#
# Note: when run as an Azure VM extension, the working dir is /var/lib/waagent/custom-script/download/0
# Author: Rich Ehrhardt
##############

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="$(pwd)"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

# Set Defaults
export TIMESTAMP=$(date +"%y%m%d-%H%M%S")
if [[ -z $SCRIPT_DIR ]]; then export SCRIPT_DIR="$(pwd)"; fi
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="${SCRIPT_DIR}"; fi
if [[ -z $OUTPUT_FILE ]]; then export OUTPUT_FILE="script-output-${TIMESTAMP}.log"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi

# Read input parameters
if [[ -z $1 ]] || [[ -z $2 ]]; then
    log-output "FATAL: Incorrect Usage."
    log-output "FATAL: Usage $0 <node> <input-parameters>"
    exit 1
else
    node=$1
    inputParameters="$2"
fi

######################DEBUG
log-output "Node type = $node"
log-output "Input Parameters = $inputParameters"
echo $inputParameters > ${SCRIPT_DIR}/inputParameters.json
#######################

export BIN_DIR=$( echo $inputParameters | jq -r .$node.binDir )
log-output "INFO: BIN_DIR set to $BIN_DIR"

# Check OS is RHEL
if [[ ! -z $(uname -r | grep ".el") ]]; then
    log-output "INFO: Confirmed RHEL OS"
else
    log-output "FATAL: Operating system could not be identified as RHEL"
    exit 1
fi

# Get RHEL OS Version
osVersion=$(hostnamectl | grep "Operating System" | awk -F '[::]' '{print $2}' | awk '{print $5}' | awk -F '[:.]' '{print $1}')

# Install az cli
if [[ -z $(which az 2> /dev/null) ]]; then
    log-output "INFO: Installing up az cli"
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    if [[ $osVersion == "8" ]]; then
        sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
    elif [[ $osVersion == "9" ]]; then
        sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
    elif [[ $osVersion == "7" ]]; then
        echo -e "[azure-cli]
            name=Azure CLI
            baseurl=https://packages.microsoft.com/yumrepos/azure-cli
            enabled=1
            gpgcheck=1
            gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
    else
        log-output "FATAL: RHEL OS version $osVersion not supported"
        exit 1
    fi

    sudo dnf -y install azure-cli

else
    log-output "INFO: az cli already exists"
fi

# Attempt to login to the azure cli
# Check if already logged in   ***************************
managedId=$(echo $inputParameters | jq -r .managedId)
if [[ -z $managedId ]]; then
    # no managed identity provided, try logging in with system supplied

    # login as system identity and get base parameters
    az login --identity 1> /dev/null 2> /dev/null
    if [[ $? != 0 ]]; then
        log-output "FATAL: Unable to login with system assigned identity"
        exit 1
    else
        log-output "INFO: Successfully logged in as system assigned identity"
    fi

    # Now try getting managed id details
    managedId=$(az identity list --query [0].id -o tsv)
    if [[ $managedId == "" ]]; then
        log-output "ERROR: No user assigned identity found, will continue with system identity"
    else
        log-output "INFO: Using user assigned identity $managedId"
        az login --identity -u $managedId 1> /dev/null 2> /dev/null
        if [[ $? != 0 ]]; then
            log-output "ERROR: Unable to login to user assigned identity $managedId"
            exit 1
        else
            log-output "INFO: Successfully logged in with user assigned identity $managedId"
        fi
    fi

else
    # Login with supplied managed identity
    log-output "INFO: Logging in with $managedId"
    az login --identity -u $managedId
    if [[ $? != 0 ]]; then
        log-output "ERROR: Unable to login with user assigned identity $managedId"
        exit 1
    else
        log-output "INFO: Successfully logged in with user assigned identity $managedId"
    fi

fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP=$(az group list --query [0].name -o tsv)

# Get installation binary path and download
binaryPathSecret=$(echo $inputParameters | jq -r .binaryPathSecret )
binaryName=$(echo $inputParameters | jq -r .binaryPath )
if [[ -z $binaryPathSecret ]]; then
    log-output "ERROR: No secret URL provided for binary"
    exit 1
else
    log-output "INFO: Attempting to retrieve secret for binary path from $binaryPathSecret"
    binaryPath=$(az keyvault secret show --id $binaryPathSecret --query 'value' -o tsv)
    wget -o ${SCRIPT_DIR}/$binaryPath $binaryPath
fi

