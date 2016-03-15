#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <sergibarroso@cdmon.com>
#
# Official CoreOS docs: https://coreos.com/os/docs/latest/cloud-config.html
#

############################ Editable vars ################################
initial_cluster=""
###########################################################################


############################# Fixed vars ##################################
envfile="/etc/environment"
new_node_name="$(cat /etc/machine-id)"
trap "rm --force --recursive ${workdir}" SIGINT SIGTERM EXIT
###########################################################################


############################## Functions ##################################
function get_ipv4() {
    interface="${1}"
    local ip
    while [ -z "${ip}" ]; do
        ip=$(ip -4 -o addr show dev "${interface}" scope global | gawk '{split ($4, out, "/"); print out[1]}')
        sleep .1
    done
    echo "${ip}"
}
###########################################################################


################################ Main #####################################
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

# Check mount point permisions
if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi

# Create cloud-config
initial_cluster="${initial_cluster},${new_node_name}=http://${COREOS_PRIVATE_IPV4}:2380"
cat > "/usr/share/oem/cdmon-cloud-config.yml" <<EOF
#cloud-config
coreos:
  etcd2:
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:4001,http://$COREOS_PRIVATE_IPV4:2379
    initial-advertise-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    initial-cluster: $initial_cluster
    initial-cluster-state: existing
    name: $new_node_name
  fleet:
    public-ip: $COREOS_PUBLIC_IPV4
  update:
    reboot-strategy: "best-effort"
  units:
    - name: etcd2.service
      command: stop
    - name: fleet.service
      command: stop
EOF
sudo sed -i 's/--oem=ec2-compat/--from-file=\/usr\/share\/oem\/cdmon-cloud-config.yml/g' /usr/share/oem/cloud-config.yml

# Exec custom file, reboot and enjoy :)
sudo coreos-cloudinit --from-file='/usr/share/oem/cdmon-cloud-config.yml'
sudo reboot
###########################################################################
