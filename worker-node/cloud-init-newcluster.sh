#!/bin/bash
#
# CoreOS Worker Role
# - Deploying a new cluster -
#
# Init script for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <sergibarroso@cdmon.com>
#
# Official CoreOS docs: https://coreos.com/os/docs/latest/cloud-config.html
#

############################ Editable vars ################################
etcd_discovery=""
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

# Check mount point permisions
if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi

# Create cloud-config
cat > "/usr/share/oem/cdmon-cloud-config.yml" <<EOF
#cloud-config
coreos:
  etcd2:
    discovery: $etcd_discovery
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:4001,http://$COREOS_PRIVATE_IPV4:2379
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
  fleet:
    metadata: "role=worker,platform=openstack,provider=adam"
    etcd_servers: "http://localhost:2379"
  update:
    reboot-strategy: "best-effort"
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
EOF
sudo sed -i 's/--oem=ec2-compat/--from-file=\/usr\/share\/oem\/cdmon-cloud-config.yml/g' /usr/share/oem/cloud-config.yml

# Exec custom file, reboot and enjoy :)
sudo coreos-cloudinit --from-file='/usr/share/oem/cdmon-cloud-config.yml'
sudo reboot
###########################################################################
