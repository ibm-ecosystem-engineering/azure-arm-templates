#!/bin/bash

function log-output() {
    MSG=${1}

    OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    mkdir -p $OUTPUT_DIR

    echo ${MSG} >> ${OUTPUT_DIR}/script-output.log
    echo ${MSG}
}

function subscription_status() {
    SUB_NAMESPACE=${1}
    SUBSCRIPTION=${2}

    CSV=$(${BIN_DIR}/oc get subscription -n ${SUB_NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(${BIN_DIR}/oc get csv -n ${SUB_NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    log-output $STATUS
}

function wait_for_subscription() {
    SUB_NAMESPACE=${1}
    export SUBSCRIPTION=${2}
    
    # Set default timeout of 15 minutes
    if [[ -z $TIMEOUT ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(subscription_status $SUB_NAMESPACE $SUBSCRIPTION) != "Succeeded" ]]; do
        log-output "INFO: Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-output "ERROR: Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done

    log-output $SUB_STATUS
}

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $TENANT_ID ]]; then ENV_VAR_NOT_SET="TENANT_ID"; fi
if [[ -z $SUBSCRIPTION_ID ]]; then ENV_VAR_NOT_SET="SUBSCRIPTION_ID"; fi
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Set default values

# Setup workspace directory
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/mnt/azscripts/azscriptoutput"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $MQ_NAMESPACE ]]; then MQ_NAMESPACE="ibm-mq"; fi
# Refer to https://www.ibm.com/docs/en/ibm-mq/9.2?topic=operator-version-support-mq for MQ operator channels
if [[ -z $OPERATOR_CHANNEL ]]; then OPERATOR_CHANNEL="v2.3"; fi
if [[ -z $CLUSTER_SCOPED ]]; then CLUSTER_SCOPED="false"; fi

# Setup temporary directories
mkdir -p $WORKSPACE_DIR
mkdir -p $TMP_DIR

#####
# Download OC and kubectl
ARCH=$(uname -m)
OC_FILETYPE="linux"
KUBECTL_FILETYPE="linux"

OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${OC_FILETYPE}.tar.gz"

# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    log-output "Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

    if ! tar tzf $TMP_DIR/openshift-client.tgz 1> /dev/null 2> /dev/null; then
        log-output "ERROR: Tar file from $OC_URL is corrupted"
        exit 1
    fi

    tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl

    mv ${TMP_DIR}/oc ${BIN_DIR}/oc
    mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl
else
    log-output "Using existing oc and kubectl binaries"
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        log-output "ERROR: Unable to login to service principal. Check supplied details in credentials.properties."
        exit 1
    else
        log-output "Successfully logged on with service principal"
    fi
    az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        log-output "ERROR: Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
        exit 1
    else
        log-output "Successfully changed to subscription : $(az account show --query name -o tsv)"
    fi
else
    log-output "Using existing Azure CLI login"
fi

#######
# Login to cluster

if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
    log-output "INFO: Logging into OpenShift cluster $ARO_CLUSTER"
    API_SERVER=$(az aro list --query "[?contains(name,'$ARO_CLUSTER')].[apiserverProfile.url]" -o tsv)
    CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
    # Below loop added to allow authentication service to start on new clusters
    count=0
    while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD 1> /dev/null 2> /dev/null ; do
        log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 15 )); then
            log-output "ERROR: Timeout waiting to log into cluster"
            exit 1;    
        fi
    done
    log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
else   
    CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
    API_SERVER=$(az aro list --query "[?contains(name,'$CLUSTER')].[apiserverProfile.url]" -o tsv)
    if [[ $CURRENT_SERVER == $API_SERVER ]]; then
        log-output "INFO: Already logged into cluster"
    else
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        # Below loop added to allow authentication service to start on new clusters
        count=0
        while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD 1> /dev/null 2> /dev/null ; do
            log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-output "ERROR: Timeout waiting to log into cluster"
                exit 1;    
            fi
        done
        log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
    fi
fi

######
# Wait for cluster operators to finish
count=0
while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
    log-output "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        log-output "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
log-output "INFO: All OpenShift cluster operators available"

######
# Create MQ namespace
if [[ -z $(${BIN_DIR}/oc get namespaces | grep $MQ_NAMESPACE ) ]]; then
    log-output "INFO: Creating namespace: ${MQ_NAMESPACE}"
    ${BIN_DIR}/oc create namespace $MQ_NAMESPACE
else
    log-output "INFO: Using existing namespace: ${MQ_NAMESPACE}"
fi

######
# Create registry secret
if [[ -z $(${BIN_DIR}/oc get secrets -n ${MQ_NAMESPACE} | grep ibm-entitlement-key) ]]; then
    log-output "INFO: Creating IBM Entitlement Key secret for namespace ${MQ_NAMESPACE}"
    ${BIN_DIR}/oc create secret -n ${MQ_NAMESPACE} docker-registry ibm-entitlement-key \
        --docker-server=cp.icr.io \
        --docker-username=cp \
        --docker-password=${IBM_ENTITLEMENT_KEY} 
else
    log-output "INFO: IBM Entitlement Key secret already exists for namespace ${MQ_NAMESPACE}"
fi

########
# Create catalog sources

# IBM Common Services operator catalog
# if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep opencloud-operators) ]]; then
#     log-output "INFO: Creating IBM Common Services catalog source"
#     if [[ -f ${WORKSPACE_DIR}/ibm-cs-catalogsource.yaml ]]; then
#         rm ${WORKSPACE_DIR}/ibm-cs-catalogsource.yaml
#     fi
#     cat << EOF >> ${WORKSPACE_DIR}/ibm-cs-catalogsource.yaml
# apiVersion: operators.coreos.com/v1alpha1
# kind: CatalogSource
# metadata:
#     name: opencloud-operators
#     namespace: openshift-marketplace
# spec:
#     displayName: IBMCS Operators
#     publisher: IBM
#     sourceType: grpc
#     image: icr.io/cpopen/ibm-common-service-catalog:latest
#     updateStrategy:
#         registryPoll:
#         interval: 45m
# EOF
#     ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/ibm-cs-catalogsource.yaml
# else
#     log-output "INFO: IBM Common Services catalog already exists"
# fi

# IBM Operator catalog
if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-operator-catalog) ]]; then
    log-output "INFO: Creating IBM Operator catalog source"
    if [[ -f ${WORKSPACE_DIR}/ibm-catalogsource.yaml ]]; then
        rm ${WORKSPACE_DIR}/ibm-catalogsource.yaml
    fi
    cat << EOF >> ${WORKSPACE_DIR}/ibm-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  image: icr.io/cpopen/ibm-operator-catalog:latest
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/ibm-catalogsource.yaml -n openshift-marketplace
else
    log-output "INFO: IBM Operator catalog source already exists"
fi

#####
# Wait for catalog to install and update
count=0
while [[ $(${BIN_DIR}/oc get packagemanifests -n openshift-marketplace | grep ibm-mq) == "" ]]; do
    log-output "INFO: Waiting for catalog to install. Waited $count minutes. Will wait up to 10 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        log-output "ERROR: Timeout waiting for catalog to install"
        exit 1
    fi
done
log-output "INFO: Catalog successfully installed"

######
# Create operator group
if [[ $CLUSTER_SCOPED != "true" ]]; then
    if [[ -z $(${BIN_DIR}/oc get operatorgroups --all-namespaces | grep mq-operator-group) ]]; then
        log-output "INFO: Creating operator group"
        if [[ -f ${WORKSPACE_DIR}/mq-operator-group.yaml ]]; then
            rm ${WORKSPACE_DIR}/mq-operator-group.yaml
        fi
        cat << EOF >> ${WORKSPACE_DIR}/mq-operator-group.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: mq-operator-group
  namespace: ${MQ_NAMESPACE}
spec:
    targetNamespaces:
    - ${MQ_NAMESPACE}
EOF
        ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/mq-operator-group.yaml
    else
        log-output "INFO: Operator group already created"
    fi
fi


######
# Create subscription
if [[ -z $(${BIN_DIR}/oc get subscriptions --all-namespaces | grep ibm-mq) ]]; then
    log-output "INFO: Creating IBM MQ subscription"
    if [[ -f ${WORKSPACE_DIR}/mq-subscription.yaml ]]; then
        rm ${WORKSPACE_DIR}/mq-subscription.yaml
    fi
    cat << EOF >> ${WORKSPACE_DIR}/mq-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mq
  namespace: openshift-operators 
spec:
  channel: v2.3
  name: ibm-mq 
  source: ibm-operator-catalog 
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/mq-subscription.yaml
else
    log-output "INFO: IBM MQ subscription already installed"
fi

wait_for_subscription openshift-operators ibm-mq 15
log-output "INFO: IBM MQ subscription ready"

######
# Start an IBM MQ instance
if [[ $LICENSE == "accept" ]] && [[ -z $(${BIN_DIR}/oc get QueueManager -n ${MQ_NAMESPACE} | grep quickstart-cp4i) ]]; then
    log-output "INFO: Creating IBM MQ Instance"
    if [[ -f ${WORKSPACE_DIR}/ibm-mq.yaml ]]; then
        rm ${WORKSPACE_DIR}/ibm-mq.yaml
    fi
    cat << EOF >> ${WORKSPACE_DIR}/ibm-mq.yaml
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  annotations:
    com.ibm.mq/write-defaults-spec: 'false'
  name: quickstart-cp4i
  namespace: ibm-mq
spec:
  license:
    accept: true
    license: L-RJON-CJR2RX
    use: NonProduction
  queueManager:
    resources:
      limits:
        cpu: 500m
      requests:
        cpu: 500m
    storage:
      queueManager:
        type: ephemeral
    name: QUICKSTART
  template:
    pod:
      containers:
        - env:
            - name: MQSNOAUT
              value: 'yes'
          name: qmgr
  web:
    enabled: true
  version: 9.3.2.0-r1
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/ibm-mq.yaml
else
    if [[ $LICENSE != "accept" ]]; then
        log-output "INFO: License not accepted. Manual creation of MQ instance required."
    else
        log-output "INFO: MQ Instance ibm-mq-quickstart in namespace ${MQ_NAMESPACE} already installed"
    fi
fi