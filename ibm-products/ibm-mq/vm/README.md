# Setup MIQM HA on Azure

## Ubuntu

1. Deploy the Azure infrastructure
    1. Click on the Deploy to Azure button above (in a new tab if you want to keep these instructions)
    2. Complete the parameters
    3. Create the installation

2. Download or copy the MQ binary tar file to both the active and standby VMs to /tmp

3. Run the install-mq-ubuntu.sh script on both the active and standby VMs
```
$ install-mq-ubuntu.sh -f /tmp/IBM_MQ_9.3.1_UBUNTU_X86-64.tar.gz -p /tmp -s /MQHA
```

4. Accept the license on both the active and standby VMs
```
$ sudo /bin/bash
# /opt/mqm/bin/mqlicense
5724-H72 (C) Copyright IBM Corp. 1994, 2022.

NOTICE

This document includes License Information documents below
for multiple Programs. Each License Information document
identifies the Program(s) to which it applies. Only those
License Information documents for the Program(s) for which
Licensee has acquired entitlements apply.


========================================


IMPORTANT: READ CAREFULLY


Press Enter to continue viewing the license agreement, or
enter "1" to accept the agreement, "2" to decline it, "3"
to print it, "4" to read non-IBM terms, or "99" to go back
to the previous screen.
1
The license agreement has been accepted.
```

Read through the license and enter "1" to accept the agreement.

5. Setup the shared directories on the active VM 

```
$ sudo mkdir -p /MQHA/logs
$ sudo mkdir -p /MQHA/qmgrs
$ sudo chown -R mqm:mqm /MQHA
$ sudo chmod -R ug+rwx /MQHA
```

6. Create the queue manager on the active VM
```
$ sudo /bin/bash
$ su - mqm
$ crtmqm -ld /MQHA/logs -md /MQHA/qmgrs QM1
IBM MQ queue manager 'QM1' created.
Directory '/MQHA/qmgrs/QM1' created.
The queue manager is associated with installation 'Installation1'.
Creating or replacing default objects for queue manager 'QM1'.
Default objects statistics : 83 created. 0 replaced. 0 failed.
Completing setup.
Setup completed.
```

7. Copy the configuration files from the active VM
```
$ dspmqinf -o command QM1
addmqinf -s QueueManager -v Name=QM1 -v Directory=QM1 -v Prefix=/var/mqm -v DataPath=/MQHA/qmgrs/QM1
```

8. Paste this command into the standby VM
```
$ addmqinf -s QueueManager -v Name=QM1 -v Directory=QM1 -v Prefix=/var/mqm -v DataPath=/MQHA/qmgrs/QM1
IBM MQ configuration information added.
```

9. Start the queue manager on the active VM
```
$ strmqm -x QM1
The system resource RLIMIT_NOFILE is set at an unusually low level for IBM MQ.
IBM MQ queue manager 'QM1' starting.
The queue manager is associated with installation 'Installation1'.
6 log records accessed on queue manager 'QM1' during the log replay phase.
Log replay for queue manager 'QM1' complete.
Transaction manager state recovered for queue manager 'QM1'.
Plain text communication is enabled.
IBM MQ queue manager 'QM1' started using V9.3.1.0.
```

10. Start the queue manager on the standby VM
```
$ strmqm -x QM1
The system resource RLIMIT_NOFILE is set at an unusually low level for IBM MQ.
IBM MQ queue manager 'QM1' starting.
The queue manager is associated with installation 'Installation1'.
Plain text communication is enabled.
A standby instance of queue manager 'QM1' has been started. The active instance
is running elsewhere.
```
