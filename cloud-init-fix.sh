#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <hiroru@lionclan.org>
#
# Official CoreOS docs: https://coreos.com/os/docs/latest/cloud-config.html
#

# Defining variables
new_cluster=false
# etcd_discovery must be set to create initial new cluster
etcd_discovery=""
# initial_cluster will be use only to add a new node, then run below command into current cluster member
# etcdctl member list | awk '{print $2"="$3}' | awk -F"=" '{print $2"="$4}' | awk '/START/{if (x)print x;x="";next}{x=(!x)?$0:x","$0;}END{print x;}'
initial_cluster="4ad401e4b56d403689f3d556c9c7bf37=http://172.31.64.149:2380,e0d9e5adb6eb4c8f94dda86770f38f88=http://172.31.64.151:2380,c233467ef98d457dbb9ca104914b6a92=http://172.31.64.150:2380"

envfile="/etc/environment"
new_node_name="$(cat /etc/machine-id)"
trap "rm --force --recursive ${workdir}" SIGINT SIGTERM EXIT

# Function list
function get_ipv4() {
    interface="${1}"
    local ip
    while [ -z "${ip}" ]; do
        ip=$(ip -4 -o addr show dev "${interface}" scope global | gawk '{split ($4, out, "/"); print out[1]}')
        sleep .1
    done
    echo "${ip}"
}

# Creating environment file
until ! [[ -z $COREOS_PRIVATE_IPV4 ]]; do
   sudo touch "$envfile"
   if [ $? -ne 0 ]; then
      echo "Error: could not write file $envfile."
   fi
   export COREOS_PUBLIC_IPV4="$(get_ipv4 eth0)"
   sudo echo "COREOS_PUBLIC_IPV4=$COREOS_PUBLIC_IPV4" > "$envfile"
   export COREOS_PRIVATE_IPV4="$(get_ipv4 eth1)"
   sudo echo "COREOS_PRIVATE_IPV4=$COREOS_PRIVATE_IPV4" >> "$envfile"
   if [ -z $etcd_discovery ]; then
      export ETCD_DISCOVERY="$etcd_discovery"
      sudo echo "ETCD_DISCOVERY=$etcd_discovery" >> "$envfile"
   fi
   source "/etc/environment"
done

# Creating custom cloud-config.yml file
if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi

if [ $new_cluster = true ]; then
cat > "/usr/share/oem/cdmon-cloud-config.yml" <<EOF
#cloud-config
coreos:
  etcd2:
    discovery: $etcd_discovery
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:2379,http://$COREOS_PRIVATE_IPV4:4001
    initial-advertise-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
  fleet:
    public-ip: $COREOS_PUBLIC_IPV4
  update:
    reboot-strategy: "etcd-lock"
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh5/Evt1CGZ1gi9AFYC5VrWx5/ppnXRflOiVoKizYCuLs7WPaRSLurOaOsXh/UoqyaEsjTw5UXuQhoLueF2krCIWeIfD1QAPOXgnbAkp1GWfS6sxlvxhHh2mi1mMrVYEt+Jg/MFW8aU8hV2iW3oAEr9UqtSLoSlQTdKjkMaRtCN4JnEp8t2xvL/xUYM+1SepdJhebSsTKLL+ogfP8j3sYvpDMmGkXdHXXFNeQ37oBZMjbEg71aP0NmCXIbzTIaiIhG6WlerlNkcDUDe4GsJFtKMXkJQaGvqIb8pXXVIpc8s7YamVzd/2ZtnctFrr4x00rFSehqvplSeGG2+FVww6mL
EOF
else
initial_cluster="${initial_cluster},${new_node_name}=http://${COREOS_PRIVATE_IPV4}:2380"
cat > "/usr/share/oem/cdmon-cloud-config.yml" <<EOF
#cloud-config
coreos:
  etcd2:
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:2379,http://$COREOS_PRIVATE_IPV4:4001
    initial-advertise-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    initial-cluster: $initial_cluster
    initial-cluster-state: existing
    name: $new_node_name
  fleet:
    public-ip: $COREOS_PUBLIC_IPV4
  update:
    reboot-strategy: "etcd-lock"
  units:
    - name: etcd2.service
      command: stop
    - name: fleet.service
      command: stop
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh5/Evt1CGZ1gi9AFYC5VrWx5/ppnXRflOiVoKizYCuLs7WPaRSLurOaOsXh/UoqyaEsjTw5UXuQhoLueF2krCIWeIfD1QAPOXgnbAkp1GWfS6sxlvxhHh2mi1mMrVYEt+Jg/MFW8aU8hV2iW3oAEr9UqtSLoSlQTdKjkMaRtCN4JnEp8t2xvL/xUYM+1SepdJhebSsTKLL+ogfP8j3sYvpDMmGkXdHXXFNeQ37oBZMjbEg71aP0NmCXIbzTIaiIhG6WlerlNkcDUDe4GsJFtKMXkJQaGvqIb8pXXVIpc8s7YamVzd/2ZtnctFrr4x00rFSehqvplSeGG2+FVww6mL
EOF
fi

sudo sed -i 's/--oem=ec2-compat/--from-file=\/usr\/share\/oem\/cdmon-cloud-config.yml/g' /usr/share/oem/cloud-config.yml

# Exec custom file, reboot and enjoy :)
sudo coreos-cloudinit --from-file='/usr/share/oem/cdmon-cloud-config.yml'
sudo reboot
