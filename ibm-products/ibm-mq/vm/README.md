# Setup MIQM HA on Azure

1. Deploy the Azure infrastructure
    1. Click on the Deploy to Azure button above (in a new tab if you want to keep these instructions)
    2. Complete the parameters
    3. Create the installation

2. Download the MQ binary tar file to the new VM

3. Run the install-mq-ubuntu.sh script

```shell
$ install-mq-ubuntu.sh -f /tmp/IBM_MQ_9.3.1_UBUNTU_X86-64.tar.gz -p /tmp
```

4. Accept the license
```shell
sudo /bin/bash
cd /opt/mqm/bin
./mqlicense
```

Read through the license and enter "1" to accept the agreement.

5. Change to the mqm user

```shell
sudo /bin/bash
su - mqm
```

6. Configure the shared directory
```shell
sudo /bin/bash
su - mqm
export LogDefaultPath=/MQHA
crtmqm -md /MQHA/qmgrs QM1
```
