#!/bin/bash

# Configuration variables
INVENTORY_FILE="inventory.ini"
PROVISION_PLAYBOOK="./server/provision_server.ansible.yml"
NGINX_PLAYBOOK="./nginx_deploy/nginx_conf.ansible.yml"
NGINX_CONFIG_FILE="./nginx_deploy/nginx_config.txt"

# Function to list all servers and allow the user to choose one
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

# Function to prompt for Nginx parameters
prompt_nginx_parameters() {
  echo "Enter the name for the generated Nginx configuration file:"
  read nginx_conf_name

  if [[ ! $nginx_conf_name == *.conf ]]; then
    nginx_conf_name="$nginx_conf_name.conf"
  fi

  echo "Enter the PORT for the Nginx:"
  read PORT

  echo "Enter the SERVER_NAME for the Nginx:"
  read SERVER_NAME

  ENABLE_RATE_LIMITING="false"
  echo "Enable rate limiting? (true/false, default is false):"
  read user_input
  [ ! -z "$user_input" ] && ENABLE_RATE_LIMITING=$user_input

  ENABLE_CACHE="false"
  echo "Enable caching? (true/false, default is false):"
  read user_input
  [ ! -z "$user_input" ] && ENABLE_CACHE=$user_input

  ENABLE_CACHE_CONTROL="false"
  echo "Enable cache control? (true/false, default is false):"
  read user_input
  [ ! -z "$user_input" ] && ENABLE_CACHE_CONTROL=$user_input

  ./generate_nginx_conf_script.sh -p $PORT -s $SERVER_NAME -r $ENABLE_RATE_LIMITING -c $ENABLE_CACHE -C $ENABLE_CACHE_CONTROL > "$NGINX_CONFIG_FILE"
}

# Main Script Starts Here
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

echo "What would you like to do?"
echo "1) Provision Server"
echo "2) Configure Nginx"
echo "3) Exit"
read choice

if [ "$choice" == "1" ]; then
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" "$PROVISION_PLAYBOOK"
elif [ "$choice" == "2" ]; then
  prompt_nginx_parameters
  nginx_ansible_extra_vars=$(cat << EOM
{
  "nginx_conf_name": "$nginx_conf_name",
  "nginx_config_file": "$NGINX_CONFIG_FILE"
}
EOM
  )
  combined_ansible_extra_vars=$(echo $ansible_extra_vars $nginx_ansible_extra_vars | jq -s 'add')
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$combined_ansible_extra_vars" "$NGINX_PLAYBOOK"
elif [ "$choice" == "3" ]; then
  echo "Exiting."
else
  echo "Invalid choice. Exiting."
fi