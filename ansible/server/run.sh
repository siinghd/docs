#!/bin/bash

INVENTORY_FILE="inventory.ini"

choose_server() {
  echo "Available servers:"
  servers=$(ansible-inventory --list -i $INVENTORY_FILE | jq -r '.servers.hosts[]')
  
  count=1
  for i in $servers; do
    echo "$count) $i"
    count=$((count + 1))
  done

  echo "Choose a server:"
  read choice

  selected_server=$(echo $servers | awk -v var="$choice" '{print $(var)}')
  target_ip=$(ansible-inventory --list -i $INVENTORY_FILE | jq -r --arg host "$selected_server" '._meta.hostvars[$host].ansible_host')
  target_user=$(ansible-inventory --list -i $INVENTORY_FILE | jq -r --arg host "$selected_server" '._meta.hostvars[$host].ansible_user')

  echo "Enter SSH password for the target server:"
  read -s ssh_password
}

choose_server

ansible_extra_vars=$(cat << EOM
{
  "ansible_host": "$target_ip",
  "ansible_user": "$target_user",
  "selected_server": "$selected_server",
  "target_user": "$target_user",
  "target_ip": "$target_ip",
  "ssh_password": "$ssh_password",
  "ansible_become_pass": "$ssh_password"
}
EOM
)

echo "Do you want to provision the server? (y/n)"
read choice

if [ "$choice" == "y" ]; then
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" provision_server.ansible.yml
else
  echo "Server provisioning skipped. Exiting."
fi
