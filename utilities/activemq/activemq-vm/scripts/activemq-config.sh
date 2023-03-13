export VERSION="5.17.4"
export ACTIVEMQ_HOME="/opt/activemq"
export PASSWORD="xyzzy"
export TMP_DIR="/tmp"
export BRANCH="initial-version"

# Update and install required CLIs
sudo apt-get update && apt-get install -y wget

# Install openjdk
sudo apt-get install -y openjdk-11-jre

# Install Apache ActiveMQ
sudo mkdir $ACTIVEMQ_HOME
sudo addgroup --quiet --system activemq
sudo adduser --quiet --system --ingroup activemq --no-create-home --disabled-password activemq
wget -P $TMP_DIR http://archive.apache.org/dist/activemq/$VERSION/apache-activemq-$VERSION-bin.tar.gz
sudo tar -xvzf $TMP_DIR/apache-activemq-$VERSION-bin.tar.gz
sudo mv $TMP_DIR/apache-activemq-$VERSION/* $ACTIVEMQ_HOME

cat << EOF >> ./activemq.service
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

sudo cp activemq.service /etc/systemd/system/

# Configure ActiveMQ access from any network
cat $ACTIVEMQ_HOME/conf/jetty.xml | sed 's/property name=\"host\" value=\"127.0.0.1\"/property name=\"host" value=\"0.0.0.0\"/g' > $TMP_DIR/jetty-updated.xml
sudo cp $TMP_DIR/jetty-updated.xml $ACTIVEMQ_HOME/conf/jetty.xml

# Configure MQ Access credentials
cat $ACTIVEMQ_HOME/conf/jetty-realm.properties | sed "s/admin: admin, admin/admin: $PASSWORD, admin/g" | sed "s/user: user, user/user: $PASSWORD, user/g" > $TMP_DIR/jetty-realm.properties
sudo cp $TMP_DIR/jetty-realm.properties $ACTIVEMQ_HOME/conf/jetty-realm.properties

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
