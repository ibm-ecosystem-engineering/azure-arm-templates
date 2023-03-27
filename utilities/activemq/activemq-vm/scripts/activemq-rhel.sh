#!/bin/bash
# 
# This script installs ActiveMQ onto a RHEL 8 server
#
# Author: Rich Ehrhardt
# Date: 24 March 2023
#

# Exit if no password provided
if [[ -z $1 ]]; then
    echo "ERROR: Missing argument"
    echo "Usage: $0 PASSWORD VERSION NEW_VM"
    echo "   where "
    echo "         PASSWORD is the MQ admin password to be set"
    echo "         VERSION is the version fo ActiveMQ to be installed"
    echo "         NEW_VM is either true or false to indicate whether the VM being deployed to is new or existing"
    exit 1;
fi

# Set version if supplied
if [[ -z $2 ]]; then
    export VERSION="5.16.3"
else
    export VERSION=$2
fi

export ACTIVEMQ_HOME="/opt/activemq"
export PASSWORD=$1
export TMP_DIR="/tmp"

# Delay start if a new build to let cloud-init scripts finish
if [[ -z $3 ]]; then NEW_VM=false; else NEW_VM=$3; fi
if [[ $NEW_VM == true ]]; then
    sleep 120
fi

# Update software
sudo yum -y update

# Install javajdk
sudo yum -y install java-11-openjdk

# Install active MQ
sudo mkdir -p $ACTIVEMQ_HOME
sudo groupadd --system activemq
sudo useradd --system -g activemq --no-create-home activemq
wget -P $TMP_DIR http://archive.apache.org/dist/activemq/$VERSION/apache-activemq-$VERSION-bin.tar.gz
sudo tar -xvzf $TMP_DIR/apache-activemq-$VERSION-bin.tar.gz -C $TMP_DIR
sudo mv $TMP_DIR/apache-activemq-$VERSION/* $ACTIVEMQ_HOME

# Setup activemq service
cat << EOF >> $TMP_DIR/activemq.service
[Unit]
Description=Apache ActiveMQ
After=network.target

[Service]
Type=forking
User=activemq
Group=activemq

WorkingDirectory=$ACTIVEMQ_HOME/bin
ExecStart=$ACTIVEMQ_HOME/bin/activemq start
ExecStop=$ACTIVEMQ_HOME/bin/activemq stop
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

sudo cp $TMP_DIR/activemq.service /etc/systemd/system/

# Configure ActiveMQ access from any network
sudo cat $ACTIVEMQ_HOME/conf/jetty.xml | sed 's/property name=\"host\" value=\"127.0.0.1\"/property name=\"host" value=\"0.0.0.0\"/g' > $TMP_DIR/jetty-updated.xml
sudo mv $TMP_DIR/jetty-updated.xml $ACTIVEMQ_HOME/conf/jetty.xml

# Configure properties
sudo cat $ACTIVEMQ_HOME/conf/jetty-realm.properties | sed "s/admin: admin, admin/admin: $PASSWORD, admin/g" | sed "s/user: user, user/user: $PASSWORD, user/g" > $TMP_DIR/jetty-realm.properties
sudo mv $TMP_DIR/jetty-realm.properties $ACTIVEMQ_HOME/conf/jetty-realm.properties

sudo chown -R activemq:activemq $ACTIVEMQ_HOME

# Allow selinux to run activemq
sudo ausearch -c '(activemq)' --raw | audit2allow -M my-activemq
sudo semodule -X 300 -i my-activemq.pp

# Open firewall for port 8161
sudo firewall-cmd --zone=public --add-port=8161/tcp --permanent
sudo firewall-cmd --reload

# Load activemq daemon
sudo systemctl daemon-reload
sudo systemctl start activemq