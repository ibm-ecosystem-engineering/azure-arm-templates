#!/bin/bash

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
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

######
# Set defaults
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $NAMESPACE ]]; then export NAMESPACE="cp4i"; fi
if [[ -z $CLUSTER_SCOPED ]]; then CLUSTER_SCOPED="false"; fi
if [[ -z $REPLICAS ]]; then REPLICAS="1"; fi
if [[ -z $STORAGE_CLASS ]]; then STORAGE_CLASS="azure-file"; fi
if [[ -z $INSTANCE_NAMESPACE ]]; then export INSTANCE_NAMESPACE=$NAMESPACE; fi

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

function subscription_status() {
    SUB_NAMESPACE=${1}
    SUBSCRIPTION=${2}

    CSV=$(${BIN_DIR}/oc get subscription -n ${SUB_NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(${BIN_DIR}/oc get csv -n ${SUB_NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    echo $STATUS
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
        echo "INFO: Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            echo "ERROR: Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}

#######
# Download and install CLI's if they do not already exist
ARCH=$(uname -m)
OC_FILETYPE="linux"
KUBECTL_FILETYPE="linux"
OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${OC_FILETYPE}.tar.gz"

if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    echo "Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

    if ! tar tzf $TMP_DIR/openshift-client.tgz 1> /dev/null 2> /dev/null; then
        echo "ERROR: Tar file from $OC_URL is corrupted"
        exit 1
    fi

    tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl

    mv ${TMP_DIR}/oc ${BIN_DIR}/oc
    mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        echo "ERROR: Unable to login to service principal. Check supplied details in credentials.properties."
        exit 1
    else
        echo "INFO: Successfully logged on with service principal"
    fi
    az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        echo "ERROR: Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
        exit 1
    else
        echo "INFO: Successfully changed to subscription : $(az account show --query name -o tsv)"
    fi
else
    echo "INFO: Using existing Azure CLI login"
fi

#######
# Login to cluster
if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
    echo "INFO: Logging into cluster"
    API_SERVER=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query apiserverProfile.url -o tsv | sed -e 's#^https://##; s#/##')
    CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
    ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
else   
    CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
    API_SERVER=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query apiserverProfile.url -o tsv | sed -e 's#^https://##; s#/##')
    if [[ $CURRENT_SERVER == $API_SERVER ]]; then
        echo "INFO: Already logged into cluster"
    else
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
    fi
fi

######
# Wait for cluster operators to finish
count=0
while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
    echo "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        echo "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
echo "INFO: All OpenShift cluster operators available"

######
# Create namespace if it does not exist
if [[ -z $(${BIN_DIR}/oc get namespaces | grep ${NAMESPACE}) ]]; then
    echo "INFO: Creating namespace ${NAMESPACE}"
    ${BIN_DIR}/oc create namespace $NAMESPACE
else
    echo "INFO: Using existing namespace $NAMESPACE"
fi

#######
# Create entitlement key secret for image pull if required
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then
    echo "INFO: Not setting IBM Entitlement key"
    if [[ $LICENSE == "accept" ]]; then
        echo "ERROR: License accepted but entitlement key not provided"
        exit 1
    fi
else
    if [[ -z $(${BIN_DIR}/oc get secret -n ${NAMESPACE} | grep ibm-entitlement-key) ]]; then
        echo "INFO: Creating entitlement key secret"
        ${BIN_DIR}/oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $NAMESPACE
    else
        echo "INFO: Using existing entitlement key secret"
    fi
fi

######
# Install catalog sources
if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-apiconnect-catalog) ]]; then
    echo "INFO: Installing IBM API Connect catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/api-connect-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-apiconnect-catalog
  namespace: openshift-marketplace
spec:
  displayName: "APIC Operators 4.10"
  image: icr.io/cpopen/ibm-apiconnect-catalog@sha256:e3950b6d9c2f86ec1be3deb6db1cb2e479592c3d288de94fe239fa9d01e6d445
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/api-connect-catalogsource.yaml
else
    echo "INFO: IBM API Connect catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-appconnect-catalog) ]]; then
    echo "INFO: Installed IBM App Connect catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/app-connect-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-appconnect-catalog
  namespace: openshift-marketplace
spec:
  displayName: "ACE Operators 7.0.0"
  image: icr.io/cpopen/appconnect-operator-catalog@sha256:89d67d6a6934f056705000855bac890f6699435a475b690c143387a5c6a1352c
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/app-connect-catalogsource.yaml
else
    echo "INFO: IBM App Connect catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-aspera-hsts-operator-catalog) ]]; then
    echo "INFO: Installed IBM Aspera catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/aspera-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-aspera-hsts-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Aspera Operators latest"
  image: icr.io/cpopen/aspera-hsts-catalog@sha256:a1c401135c5a4a9f3c88e2ac9b75299b9be376d6f97f34d7f68f2a31f0c726cd
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/aspera-catalogsource.yaml
else
    echo "INFO: IBM Aspera catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-cloud-databases-redis-catalog) ]]; then
    echo "INFO: Installed IBM Cloud databases Redis catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/redis-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-cloud-databases-redis-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Redis for Aspera Operators 1.6.2"
  image: icr.io/cpopen/ibm-cloud-databases-redis-catalog@sha256:68dfcc9bb5b39990171c30e20fee337117c7385a07c4868efd28751d15e08e9f
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/redis-catalogsource.yaml
else
    echo "INFO: IBM Cloud databases Redis catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-common-service-catalog) ]]; then
    echo "INFO: Installing IBM Common services catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-common-service-catalog
  namespace: openshift-marketplace
spec:
  displayName: "IBMCS Operators v3.22.0"
  image: icr.io/cpopen/ibm-common-service-catalog@sha256:36c410c39a52c98919f22f748e67f7ac6d3036195789d9cfbcd8a362dedbb2bd
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml
else
    echo "INFO: IBM common services catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-datapower-operator-catalog) ]]; then
    echo "INFO: Installing IBM Data Power catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/data-power-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-datapower-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "DP Operators 1.6.5"
  image: icr.io/cpopen/datapower-operator-catalog@sha256:244827e90e194fc92e0d60d5da7ec434d2711139ea1392f816a05bde83da386a
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/data-power-catalogsource.yaml
else
    echo "INFO: IBM Data Power catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-eventstreams-catalog) ]]; then
    echo "INFO: Installing IBM Event Streams catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/event-streams-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-eventstreams-catalog
  namespace: openshift-marketplace
spec:
  displayName: "ES Operators v3.1.3"
  image: icr.io/cpopen/ibm-eventstreams-catalog@sha256:803f7f8de9d3e2d52878ec78da6991917cfe21af937ab39009e2f218bf6ac0a1
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/event-streams-catalogsource.yaml
else
    echo "INFO: IBM Event Streams catalog source already exists"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-asset-repository-catalog) ]]; then
    echo "INFO: Installing IBM Integration Asset Repository catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-asset-repository-catalog
  namespace: openshift-marketplace
spec:
  displayName: "AR Operators 1.5.4"
  image: icr.io/cpopen/ibm-integration-asset-repository-catalog@sha256:89cd0b2bfc66241cfaf542de906982434c23d1c6391db72fc6ef99d851568abe
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml
else
    echo "INFO: IBM Integration Asset Repository catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-operations-dashboard-catalog) ]]; then
    echo "INFO: Installing IBM Integration Operations Dashboard catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-operations-dashboard-catalog
  namespace: openshift-marketplace
spec:
  displayName: "OD Operators 2.6.6"
  image: icr.io/cpopen/ibm-integration-operations-dashboard-catalog@sha256:adca1ed1a029ec648c665e9e839da3a7d20e533809706b72e7e676c665d2d7b3
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml
else
    echo "INFO: IBM Integration Operations Dashboard catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-platform-navigator-catalog) ]]; then
    echo "INFO: Installing IBM Integration Platform Navigator catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-platform-navigator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "PN Operators 7.0.0"
  image: icr.io/cpopen/ibm-integration-platform-navigator-catalog@sha256:d98a7858cef16b558969d8cb5490f0916e89ad8fd4ca5baa0ce20580ccf9bef6
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/platform-navigator-catalogsource.yaml
else
    echo "INFO: IBM Integration Platform Navigator catalog source already installed"
fi

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-mq-operator-catalog) ]]; then
    echo "INFO: Installing IBM MQ Operator catalog source"
    cat << EOF >> ${WORKSPACE_DIR}/mq-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-mq-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "MQ Operators v2.2.1"
  image: icr.io/cpopen/ibm-mq-operator-catalog@sha256:8de83ff5531de8df3ca639f612480f95ccd39a26e85a1bbdf18c7375dc93917a
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/mq-catalogsource.yaml
else
    echo "INFO: IBM MQ catalog source already installed"
fi

#######
# Create operator group if not using cluster scope
if [[ $CLUSTER_SCOPED != "true" ]]; then
    if [[ -z $(${BIN_DIR}/oc get operatorgroups -n ${NAMESPACE} | grep $NAMESPACE-og ) ]]; then
        echo "INFO: Creating operator group for namespace ${NAMESPACE}"
        cat << EOF >> ${WORKSPACE_DIR}/operator-group.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${NAMESPACE}-og
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/operator-group.yaml
    else
        echo "INFO: Using existing operator group"
    fi
fi

######
# Create subscriptions

# IBM Common Services operator
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Common Services"
    cat << EOF >> ${WORKSPACE_DIR}/common-services-sub.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: ibm-common-service-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/common-services-sub.yaml
else
    echo "INFO: IBM Common Services subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace 15
echo "INFO: IBM Common Services subscription ready"
echo

# IBM Cloud Redis Databases
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Cloud Redis databases"
    cat << EOF >> ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-cloud-databases-redis-operator
  source: ibm-cloud-databases-redis-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml
else
    echo "INFO: IBM Cloud Redis databases subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace 15
echo "INFO: IBM Cloud Redis databases subscription ready"
echo

# Platform Navigator subscription
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Integration Platform Navigator"
    cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-platform-navigator
  source: ibm-integration-platform-navigator-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/platform-navigator-subscription.yaml
else
    echo "INFO: IBM Integration Platform Navigator subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace 15
echo "INFO: IBM Integration Platform Navigator subscription ready"
echo

# Aspera
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Aspera"
    cat << EOF >> ${WORKSPACE_DIR}/aspera-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: aspera-hsts-operator
  source: ibm-aspera-hsts-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/aspera-subscription.yaml
else
    echo "INFO: IBM Aspera subscription already exists"
fi

wait_for_subscription ${NAMESPACE} aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace 15
echo "INFO: IBM Aspera subscription ready"
echo

# App Connection
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM App Connect"
    cat << EOF >> ${WORKSPACE_DIR}/app-connect-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-appconnect
  source: ibm-appconnect-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/app-connect-subscription.yaml
else
    echo "INFO: IBM App Connect Subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace 15
echo "INFO: IBM App Connect subscription ready"
echo

# Eventstreams
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating IBM Event Streams subscription"
    cat << EOF >> ${WORKSPACE_DIR}/event-streams-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-eventstreams
  source: ibm-eventstreams-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/event-streams-subscription.yaml
else
    echo "INFO: IBM Event Streams subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace 15
echo "INFO: IBM App Connect subscription ready"
echo

# MQ
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-mq-ibm-mq-operator-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM MQ"
    cat << EOF >> ${WORKSPACE_DIR}/mq-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mq-ibm-mq-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-mq
  source: ibm-mq-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/mq-subscription.yaml
else
    echo "INFO: IBM MQ subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-mq-ibm-mq-operator-catalog-openshift-marketplace 15
echo "INFO: IBM MQ subscription ready"
echo

# Asset Repo
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Integration Asset Repository"
    cat << EOF >> ${WORKSPACE_DIR}/asset-repo-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-asset-repository
  source: ibm-integration-asset-repository-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/asset-repo-subscription.yaml
else
    echo "INFO: IBM Integration Asset Repository subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace 15
echo "INFO: IBM Integration Asset Repository subscription ready"
echo

# Data power
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Data Power"
    cat << EOF >> ${WORKSPACE_DIR}/data-power-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: datapower-operator
  source: ibm-datapower-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/data-power-subscription.yaml
else
    echo "INFO: IBM Data Power subscription already exists"
fi

wait_for_subscription ${NAMESPACE} datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace 15
echo "INFO: IBM Data Power subscription ready"
echo

# API Connect
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM API Connect"
    cat << EOF >> ${WORKSPACE_DIR}/api-connect-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-apiconnect
  source: ibm-apiconnect-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/api-connect-subscription.yaml
else
    echo "INFO: IBM API Connect subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace 15
echo "INFO: IBM API Connect subscription ready"
echo

# Operations Dashboard
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace) ]]; then
    echo "INFO: Creating subscription for IBM Integration Operations Dashboard"
    if [[ -f ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml ]]; then
        rm ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml
    fi
    cat << EOF >> ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-operations-dashboard
  source: ibm-integration-operations-dashboard-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml
else
    echo "INFO: IBM Integration Operations Dashboard already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace 15
echo "INFO: IBM Integration Operations Dashboard ready"
echo


######
# Create platform navigator instance
if [[ $LICENSE == "accept" ]]; then
    if [[ -z $(${BIN_DIR}/oc get PlatformNavigator -n ${INSTANCE_NAMESPACE} | grep ${INSTANCE_NAMESPACE}-navigator ) ]]; then
        echo "INFO: Creating Platform Navigator instance"
        if [[ -f ${WORKSPACE_DIR}/platform-navigator-instance.yaml ]]; then
            rm ${WORKSPACE_DIR}/platform-navigator-instance.yaml
        fi
        cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-instance.yaml
apiVersion: integration.ibm.com/v1beta1
kind: PlatformNavigator
metadata:
  name: ${INSTANCE_NAMESPACE}-navigator
  namespace: ${INSTANCE_NAMESPACE}
spec:
  license:
    accept: true
    license: L-RJON-CJR2RX
  mqDashboard: true
  replicas: ${REPLICAS}
  version: 2022.4.1
  storage:
    class: ${STORAGE_CLASS}
EOF
        ${BIN_DIR}/oc create -n ${INSTANCE_NAMESPACE} -f ${WORKSPACE_DIR}/platform-navigator-instance.yaml
    else
        echo "INFO: Platform Navigator instance already exists for namespace ${INSTANCE_NAMESPACE}"
    fi

    count=0
    while [[ $(oc get PlatformNavigator -n ${namespace} ${namespace}-navigator -o json | jq -r '.status.conditions[] | select(.type=="Ready").status') != "True" ]]; do
        echo "INFO: Waiting for Platform Navigator instance to be ready. Waited $count minutes. Will wait up to 90 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 90)); then    # Timeout set to 90 minutes
            echo "ERROR: Timout waiting for ${INSTANCE_NAMESPACE}-navigator to be ready"
            exit 1
        fi
    done
else
    echo "INFO: License not accepted. Please manually install desired components"
fi