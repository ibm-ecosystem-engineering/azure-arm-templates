#!/bin/bash

########################################################
#
# This script will install and configure 
########################################################

function usage()
{
   echo "Sets up IBM MQ from tar file."
   echo
   echo "Usage: $0 -f TAR_FILE "
   echo "  options:"
   echo "  -f     the full path and file name of the tar file containing the IBM MQ Ubuntu binary (e.g. /tmp/IBM_MQ_9.3.1_UBUNTU_X86-64.tar.gz )"
   echo "  -p     (optional) the full path to the temporary directory to unpack the tar file. Will default to /tmp "
   echo "  -s     (optional) the full path to the share directory to host message queue and logs. Will default to /MQHA"
   echo "  -h     Print this help"
   echo
}

# Get the command line args
# Get the options
while getopts ":f:p:s:h" option; do
   case $option in
      h) # display Help
         usage
         exit 1;;
      f) # Enter a flavor
         TAR_FILENAME=$OPTARG;;
      p) # Enter a distribution
         INSTALL_BIN_PATH=$OPTARG;;
      s) # Share path
         SHARE_PATH=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         usage
         exit 1;;
   esac
done

# Set default
if [[ -z $INSTALL_BIN_PATH ]]; then INSTALL_BIN_PATH="/tmp"; fi
if [[ -z $SHARE_PATH ]]; then SHARE_PATH="/MQHA"; fi
MQ_INSTALL_PATH="/opt/mqm"

# Create install directory
mkdir -p $INSTALL_BIN_PATH

# Extract tar file to install directory
tar xvf $TAR_FILENAME -C $INSTALL_BIN_PATH

# Make install files accessible by apt-get
chmod -R a+rw $INSTALL_BIN_PATH/MQServer

cd $INSTALL_BIN_PATH/MQServer

# Create local repo for install directory
echo "deb [trusted=yes] file:${INSTALL_BIN_PATH}/MQServer ./" | sudo tee /etc/apt/sources.list.d/ibm-mq.list
sudo apt-get update

# Install IBM MQ
sudo apt-get install "ibmmq-*"

# Set the installed version to the primary installation for IBM MQ
sudo ${MQ_INSTALL_PATH}/bin/setmqinst -i -p ${MQ_INSTALL_PATH}

# Setup subdirectories
sudo mkdir -p ${SHARE_PATH}/log
sudo mkdir -p ${SHARE_PATH}/qmgrs

# Set permissions on shared directory
sudo chown -R mqm:mqm ${SHARE_PATH}
