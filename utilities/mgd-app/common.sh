#!/bin/bash

function az-login() {
    CLIENT_ID=${1}
    CLIENT_SECRET=${2}
    TENANT_ID=${3}
    SUBSCRIPTION_ID=${4}

    if [[ -z $CLIENT_ID ]] || [[ -z $CLIENT_SECRET ]] || [[ -z $TENANT_ID ]] || [[ -z $SUBSCRIPTION_ID ]]; then
        log-output "ERROR: Incorrect usage. Supply client id, client secret, tenant id and subcription id to login"
        exit 1
    fi

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
}

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function reset-output() {
    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    if [[ -f ${OUTPUT_DIR}/${OUTPUT_FILE} ]]; then
        cp ${OUTPUT_DIR}/${OUTPUT_FILE} ${OUTPUT_DIR}/${OUTPUT_FILE}-$(date -u +"%Y%m%d-%H%M%S").log
        rm ${OUTPUT_DIR}/${OUTPUT_FILE}
    fi
    
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

function menu() {
    local item i=1 numItems=$#

    for item in "$@"; do
        printf '%s %s\n' "$((i++))" "$item"
    done >&2

    while :; do
        printf %s "${PS3-#? }" >&2
        read -r input
        if [[ -z $input ]]; then
            break
        elif (( input < 1 )) || (( input > numItems )); then
          echo "Invalid Selection. Enter number next to item." >&2
          continue
        fi
        break
    done

    if [[ -n $input ]]; then
        printf %s "${@: input:1}"
    fi
}

function get_region() {
    if [[ -z $METADATA_FILE ]]; then
        METADATA_FILE="$(pwd)/azure-metadata.yaml"
    fi

    IFS=$'\n'

    echo
    read -r -d '' -a AREAS < <(yq '.regions[].area' $METADATA_FILE | sort -u)
    DEFAULT_AREA="$(yq ".regions[] | select(.code == \"$DEFAULT_REGION\") | .area" $METADATA_FILE)"
    PS3="Select the deployment area [$DEFAULT_AREA]: "
    area=$(menu "${AREAS[@]}")
    case $area in
        '') AREA="$DEFAULT_AREA"; ;;
        *) AREA=$area; ;;
    esac

    echo
    read -r -d '' -a REGIONS < <(yq ".regions[] | select(.area == \"${AREA}\") | .name" $METADATA_FILE | sort -u)
    if [[ $AREA != $DEFAULT_AREA ]]; then
        DEFAULT_REGION="$(yq ".regions[] | select(.name == \"${REGIONS[0]}\") | .code" $METADATA_FILE)"
    fi
    PS3="Select the region within ${AREA} [$(yq ".regions[] | select(.code == \"$DEFAULT_REGION\") | .name" $METADATA_FILE)]: "
    region=$(menu "${REGIONS[@]}")
    case $region in
        '') REGION="$DEFAULT_REGION"; ;;
        *) REGION="$(yq ".regions[] | select(.name == \"$region\") | .code" $METADATA_FILE)"; ;;
    esac

    echo $REGION
}