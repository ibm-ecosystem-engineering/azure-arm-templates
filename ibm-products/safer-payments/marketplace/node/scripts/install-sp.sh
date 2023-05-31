#!/bin/bash

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
if [[ -z $BIN_FILE ]]; then export BIN_FILE="Safer_Payments_6.5_mp-ml.tar"; fi
if [[ -z $CLUSTER_CONFIG_FILE ]]; then export CLUSTER_CONFIG_FILE="cluster.iris.json"; fi
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="${SCRIPT_DIR}"; fi
if [[ -z $OUTPUT_FILE ]]; then export OUTPUT_FILE="script-output-${TIMESTAMP}.log"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $INSTALL_DIR ]]; then export INSTALL_DIR="/usr/ibm/safer_payments/install"; fi
if [[ -z $INSTANCE_DIR ]]; then export INSTANCE_DIR="/usr/ibm/safer_payments/instance"; fi
if [[ -z $SPUSER ]]; then export SPUSER="spuser"; fi
if [[ -z $SPGROUP ]]; then export SPGROUP="spgroup"; fi
if [[ -z $NODE_TYPE ]]; then export NODE_TYPE="primary"; fi
if [[ -z $NODE1_IP ]]; then export NODE1_IP="10.0.0.4"; fi
if [[ -z $NODE2_IP ]]; then export NODE1_IP="10.0.0.5"; fi
if [[ -z $NODE3_IP ]]; then export NODE1_IP="10.1.0.4"; fi

# Download safer payments binary
# wget -O ${SCRIPT_DIR}/${BIN_FILE} "${FILE_URL_WITH_SAS_TOKEN}"

# Extract the files
if [[ -f ${SCRIPT_DIR}/${BIN_FILE} ]]; then
    log-output "INFO: Extracting archive ${BIN_FILE}"
    tar xf ${SCRIPT_DIR}/${BIN_FILE} -C ${SCRIPT_DIR}
else
    log-output "ERROR: Unable to find ${BIN_FILE} in ${SCRIPT_DIR}"
    exit 1
fi


# Get zip file and unzip
zipFiles=( $( find ${SCRIPT_DIR}/SaferPayments*.zip ) )
if (( ${#zipFiles[@]} > 0 )); then 
    unzip ${zipFiles[0]}
else
    log-output "ERROR: Safer Payments zip file not found in ${BIN_FILE}"
    exit 1
fi

# Setup the Java Runtime Environment

jreFiles=( $( find ${SCRIPT_DIR}/ibm_jre*.vm ))
if (( ${#jreFiles[@]} > 0 )); then
  unzip ${jreFiles[0]}
else
  log-output "ERROR: ibm_jre file not found"
  exit 1
fi
sudo tar xf ${SCRIPT_DIR}/vm.tar.Z -C ${BIN_DIR}
sudo chmod +x ${BIN_DIR}/jre/bin/java
chmod +x ${SCRIPT_DIR}/SaferPayments.bin

# Run safer payments installation
# Accept the license
sed -i 's/LICENSE_ACCEPTED=FALSE/LICENSE_ACCEPTED=TRUE/g' ${SCRIPT_DIR}/installer.properties

# Change install path to be under /usr
sed -i 's/USER_INSTALL_DIR/#USER_INSTALL_DIR/g' ${SCRIPT_DIR}/installer.properties
echo "USER_INSTALL_DIR=${INSTALL_DIR}" >> ${SCRIPT_DIR}/installer.properties

log-output "INFO: Installing Safer Payments to ${INSTALL_DIR}"
sudo env "PATH=${BIN_DIR}/jre/bin:$PATH" ./SaferPayments.bin -i silent

# Create user and group to run safer payments
sudo adduser --system ${SPUSER}
sudo groupadd ${SPGROUP}
sudo usermod -a -G ${SPGROUP} ${SPUSER}

# Run safer payments postrequisites
sudo mkdir -p ${INSTANCE_DIR}
sudo cp -R ${INSTALL_DIR}/factory_reset/* ${INSTANCE_DIR} 
sudo chown -R ${SPUSER}:${SPGROUP} ${INSTANCE_DIR}

# Open firewall ports
if [[ -z $NODE_TYPE == "primary" ]]; then
    sudo firewall-cmd --zone=public --add-port=8001/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27921/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27931/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27941/tcp --permanent
elif [[ -z $NODE_TYPE == "ha" ]]; then
    sudo firewall-cmd --zone=public --add-port=8002/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27922/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27932/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27942/tcp --permanent
elif [[ -z $NODE_TYPE == "dr" ]]; then
    sudo firewall-cmd --zone=public --add-port=8003/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27923/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27933/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27943/tcp --permanent
fi
sudo firewall-cmd --reload

# Setup cluster

# Configure safer payments as a service
if [[ -f ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE} ]]; then
    log-output "INFO: Configuring cluster settings"
    sed -i 's,INSTANCE_DIR,'"$INSTANCE_DIR"',' ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE} 
    sed -i 's,NODE1_IP,'"${NODE1_IP}"',' ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE}
    sed -i 's,NODE2_IP,'"${NODE2_IP}"',' ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE}
    sed -i 's,NODE3_IP,'"${NODE3_IP}"',' ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE}
    sudo cp ${SCRIPT_DIR}/${CLUSTER_CONFIG_FILE} ${INSTANCE_DIR}/cfg/cluster.iris
else
    log-output "ERROR: Cluster config template ${CLUSTER_CONFIG_FILE} not found in ${SCRIPT_DIR}"
    exit 1
fi 

# On primary

# Write custom /instancePath/cfg/cluster.iris to primary node
# Copy instancePath/* to other nodes

log-output "INFO: Installation complete"