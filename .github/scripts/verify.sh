#!/bin/bash

if [[ -z $1 ]]; then
 echo "ERROR: Missing argument"
 echo "Usage: $0 FILENAME"
 echo "where"
 echo "    FILENAME is the type of file to search and verify. For example, azuredeploy.json"
 exit 1
fi

#WORKSPACE_DIR="/workspace"
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

# Check azuredeploy files
echo "Checking $1 files"
cd ${WORKSPACE_DIR}

# Get list of files to check
find "${WORKSPACE_DIR}" -name "$1" | grep -v "${TTK_DIR}" | while read azfile
do
    echo "Checking $azfile..."
    outfile_name=$(echo $azfile | awk '{n=split($0,a,"/"); print a[n-2],"-",a[n-1]}' | sed 's/\ //g')
    ${TTK_DIR}/arm-ttk/Test-AzTemplate.sh -TemplatePath ${azfile} -Skip apiVersions-Should-Be-Recent,Template-Should-Not-Contain-Blanks | tee ${TMP_DIR}/${outfile_name}.out
    
    #Look for failures
    cat ${TMP_DIR}/${outfile_name}.out | while read line
    do
        failures=$(echo $line | grep "Fail" | grep -v ": 0" | awk '{split($0,a," : "); print a[2]}')
        if [[ -n $failures ]] && [[ $failures != "0" ]]; then
            touch ${TMP_DIR}/${outfile_name}-fail
        fi
    done

    if [[ -f ${TMP_DIR}/${outfile_name}-fail ]]; then
        echo "$azfile" >> ${TMP_DIR}/fail
        rm ${TMP_DIR}/${outfile_name}-fail
    fi
done

basePath=$(echo ${WORKSPACE_DIR} | sed 's/\//:/g')

if [[ -f ${TMP_DIR}/fail ]]; then
    echo "The following scripts failed"
    cat ${TMP_DIR}/fail | sed 's/\//:/g' | sed "s/${basePath}//g" | sed 's/:/\//g'
    rm ${TMP_DIR}/fail
    exit 1
else
    echo "All tests passed"
fi