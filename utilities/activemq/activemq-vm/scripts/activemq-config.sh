#!/bin/bash

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
export BRANCH="main"

# Wait for cloud-init to finish
count=0
while [[ $(ps xua | grep cloud-init | grep -v grep) ]]; do
    echo "Waiting for cloud init to finish. Waited $count minutes. Will wait 15 mintues."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        echo "ERROR: Timeout waiting for cloud-init to finish"
        exit 1;
    fi
done

# Update software repo
sudo apt-get update

# Install openjdk and wget
sudo apt-get install -y openjdk-11-jre wget

# Install Apache ActiveMQ
sudo mkdir -p $ACTIVEMQ_HOME
sudo addgroup --quiet --system activemq
sudo adduser --quiet --system --ingroup activemq --no-create-home --disabled-password activemq
wget -P $TMP_DIR http://archive.apache.org/dist/activemq/$VERSION/apache-activemq-$VERSION-bin.tar.gz
sudo tar -xvzf $TMP_DIR/apache-activemq-$VERSION-bin.tar.gz -C $TMP_DIR
sudo mv $TMP_DIR/apache-activemq-$VERSION/* $ACTIVEMQ_HOME

cat << EOF >> $TMP_DIR/activemq.service
[Unit]
Description=Apache ActiveMQ
After=network.target

[Service]
Type=forking
User=activemq
Group=activemq

ExecStart=$ACTIVEMQ_HOME/bin/activemq start
ExecStop=$ACTIVEMQ_HOME/bin/activemq stop

[Install]
WantedBy=multi-user.target

EOF

sudo cp $TMP_DIR/activemq.service /etc/systemd/system/

# Configure ActiveMQ access from any network
sudo cat $ACTIVEMQ_HOME/conf/jetty.xml | sed 's/property name=\"host\" value=\"127.0.0.1\"/property name=\"host" value=\"0.0.0.0\"/g' > $TMP_DIR/jetty-updated.xml
sudo mv $TMP_DIR/jetty-updated.xml $ACTIVEMQ_HOME/conf/jetty.xml

# Configure MQ Access credentials
sudo cat $ACTIVEMQ_HOME/conf/jetty-realm.properties | sed "s/admin: admin, admin/admin: $PASSWORD, admin/g" | sed "s/user: user, user/user: $PASSWORD, user/g" > $TMP_DIR/jetty-realm.properties
sudo mv $TMP_DIR/jetty-realm.properties $ACTIVEMQ_HOME/conf/jetty-realm.properties

# Configure initial queue
wget -P $TMP_DIR https://raw.githubusercontent.com/ibm-ecosystem-lab/azure-arm-templates/$BRANCH/utilities/activemq/activemq-vm/files/activemq.xml
sudo cp $TMP_DIR/activemq.xml $ACTIVEMQ_HOME/conf/activemq.xml

# Configure JNDI access


# Set file permissions to activemq user
sudo chown -R activemq:activemq $ACTIVEMQ_HOME

# Load activeMQ as a daemon
sudo systemctl daemon-reload
sudo systemctl start activemq
sudo systemctl enable activemq
