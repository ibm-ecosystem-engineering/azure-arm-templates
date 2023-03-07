#!/bin/bash

WORKSPACE_DIR="/mnt"


# Check azuredeploy files
echo "Checking azuredeploy.json files"

# Get list of files to check
find "${WORKSPACE_DIR}" -name "azuredeploy.json" | while read azfile
do
    echo "Checking $azfile"
done