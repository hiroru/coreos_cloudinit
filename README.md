# CoreOS cluster cloud-init fix

## Description
This script was created to fill the gap by the lack of meta-data service on the Adam's Public Cloud.

## How to use it
To properly deploy a CoreOS Cluster in the Adam's Openstack just follow the next few steps:

1. Start Launch Instances menu
2. Choose your custom detail information but pay attention to Flavor which should be *m1.medium* at worst and to *Instance Count* which will be used later.
3. In *Access & security* tap you must check *default* and *coreos* Security Groups.
4. Add *tenant-cdmonexternal-net* and *tenant-cdmoninternal-net* into the *Selected networks*
5. It's the turn for the script to enter the scene. Edit *ETCD_DISCOVERY* inside the script with the text returned by `https://discovery.etcd.io/new?size=$numnodes`
6. Inside *Post-Creation* tab select *File* into drop-down menu to select this script.
7. Finally in the *Advanced Options* check the *Configuration Drive* option.
8. Ignition!
