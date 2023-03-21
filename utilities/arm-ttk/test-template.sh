#!/bin/bash

if [[ -z $1 ]]; then
 echo "ERROR: Missing argument"
 echo "Usage: $0 FILENAME"
 echo "where"
 echo "    FILENAME is file to verify. For example, azuredeploy.json"
 exit 1
fi

WORKSPACE_DIR=$(pwd)
TMP_DIR=${WORKSPACE_DIR}/tmp
TTK_DIR=${WORKSPACE_DIR}/tmp/arm-ttk

mkdir -p $TMP_DIR

# Clone ARM TTK repository
if [[ -d ${TTK_DIR} ]]; then
    echo "Using existing ARM TTK instance"
else
    echo "Cloning Azure ARM TTK repository"
    git clone -q https://github.com/Azure/arm-ttk.git ${TTK_DIR}
fi

${TTK_DIR}/arm-ttk/Test-AzTemplate.sh -TemplatePath $1 -Skip apiVersions-Should-Be-Recent,Template-Should-Not-Contain-Blanks