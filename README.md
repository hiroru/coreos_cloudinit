# CoreOS cluster cloud-init fix

## Description
This script was created to fill the gap by the lack of meta-data service on the Adam's Public Cloud.

## How to use it
To properly deploy a CoreOS Cluster in the Adam's Openstack just follow the next few steps:

### Deploy a new cluster
Before deploying a new cluster we must decide the size which it will has. Depending on the number of nodes we can reach an optimal fault tolerance platform:

| Cluster size | Majority | Failure Tolerance |
|--------------|----------|-------------------|
| 1            | 1        | 0                 |
| 3            | 2        | 1                 |
| 4            | 3        | 1                 |
| 5            | 3        | 2                 |
| 6            | 4        | 2                 |
| 7            | 4        | 3                 |
| 8            | 5        | 3                 |
| 9            | 5        | 4                 |

Just we can see in the table above It is recommended to have an odd number of members in a cluster, 3-5-7-9 and so on.

Unfortunately, standard options it's not enough to get it working inside Adam's OpenStack platform, so the lack of meta-data service forced us to create a script to solve some problems.

**Repository**
https://bitbucket.org/cdmontech/coreos-cloudinit-fix

To properly deploy a CoreOS Cluster in the Adam's Openstack just follow the next few steps:

1. Start Launch Instances menu
2. Choose your custom detail information but pay attention to Flavor which should be m1.medium at worst and to Instance Count which will be used later.
3. In Access & security tap you must check default and coreos Security Groups.
4. Add tenant-cdmonexternal-net and tenant-cdmoninternal-net into the Selected networks
5. It's the turn for the script to enter the scene:
6. Edit ETCD_DISCOVERY inside the script with the text returned by https://discovery.etcd.io/new?size=$numnodes
7. Check if new_cluster variable is set to true
8. Inside Post-Creation tab select File into drop-down menu to select this script. and check that
9. Finally in the Advanced Options check the Configuration Drive option.
10. Ignition!

### Growing and shrink the cluster size
#### Removing node from cluster
1. First we need to list the current cluster nodes in a member of the cluster:
    `etcdctl member list`
2. Use the first field as _MEMBER_ID_:
    `etcdctl member remove _MEMBER_ID_`
3. Then we must wait until etcd2 in the removed node returns "the member has been permanently removed from the cluster" message.

#### Adding node to cluster
Keep in mind that to add a new member to a cluster is a manual process, it's recommended to add it one by one. The procedure is described below:

1. Run the next command into any node from the current cluster:
    ```
    etcdctl member list | awk '{print $2"="$3}' | awk -F"=" '{print $2"="$4}' | awk '/START/{if (x)print x;x="";next}{x=(!x)?$0:x","$0;}END{print x;}'`
    ```

    And you will get an output like:
    ```
    4ad401e4b56d403689f3d556c9c7bf37=http://172.31.64.149:2380,e0d9e5adb6eb4c8f94dda86770f38f88=http://172.31.64.151:2380,fc69854b6bd9428f8181c7a76797a313=http://172.31.64.152:2380,c233467ef98d457dbb9ca104914b6a92=http://172.31.64.150:2380
    ```

    Simply copy and paste into initial_cluster variable from cloud-init-fix.sh file.

2. Edit cloud-init-fix.sh file and set initial_cluster variable value with the output you got above and then set new_cluster to false.

    Once you get your new node up & running access it through ssh and keep the _NEW_NODE_ID_ from running:
    `cat /etc/machine-id`

3. Then run the next commands into any node from the current cluster (not the new one):
    `etcdctl member add _NEW_NODE_ID_ http://_NEW_NODE_PRIVATE_IP_:2380`
    Skip the text returned from that command.

4. Back to the ssh shell in the new node and you can now start etcd2 and the fleet by:
    ```
    systemctl start etcd2 && systemctl start fleet
    systemctl enable etcd2 && systemctl enable fleet
    ```

5. Enjoy (smile)

### Migrate/Update a member
1. Stop etcd2 in the old member
    `systemctl stop etcd2`

2. Copy the data directory from now-idle member to the new machine
    ```
    tar -cvzf etcd2.tar.gz /var/lib/etcd2
    scp etcd2.tar.gz _NEW_NODE_PRIVATE_IP_:~/
    ```

3. Update the peer URLs for that member to reflect the new machine, this must be run in an active member of the cluster, neither in the now-idle member nor new machine.
    `etcdctl member update _OLD_MEMBER_ID_ http://_NEW_MEMBER_IP_:2380`

4. Start etcd2 on the new machine, using the same configuration and data:
    ```
    tar -xzvf etcd2.tar.gz /
    systemctl start etcd2
    ```

5. Now we can remove the old member instance. (smile)

### Disaster Recovery
1. We should remove failed node from cluster to avoid *etcd* to continue checking its status:
    `etcdctl member list`

2. Check the failed member ID
    `etcdctl member remove _FAILED_MEMBER_ID_`

3. And new follow the ADD new node procedure to bring up a new node.
