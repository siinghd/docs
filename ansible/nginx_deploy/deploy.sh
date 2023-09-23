#!/bin/bash

# Define the Ansible inventory file
INVENTORY_FILE="inventory.ini"

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

  # Prompt for SSH password
  echo "Enter SSH password for the target server:"
  read -s ssh_password
}
# Function to prompt for Nginx parameters
prompt_nginx_parameters() {
  echo "Enter the name for the generated Nginx configuration file:"
  read nginx_conf_name
  
  # Check if the filename ends with .conf and append it if not
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

  # Generate and save the Nginx config to a temp file
  ./generate_nginx_conf_script.sh -p $PORT -s $SERVER_NAME -r $ENABLE_RATE_LIMITING -c $ENABLE_CACHE -C $ENABLE_CACHE_CONTROL > ./nginx_config.txt
}
# Main Script Starts Here
choose_server
prompt_nginx_parameters

ansible_extra_vars=$(cat << EOM
{
  "ansible_host": "$target_ip",
  "ansible_user": "$target_user",
  "selected_server": "$selected_server",
  "target_user": "$target_user",
  "target_ip": "$target_ip",
  "ssh_password": "$ssh_password",
  "ansible_become_pass": "$ssh_password",
  "nginx_conf_name": "$nginx_conf_name",
  "nginx_config_file": "./nginx_config.txt"
}
EOM
)

echo "Do you want to 1) Create Nginx conf, 2) Create execution script, or 3) Do both?"
read choice

if [ "$choice" == "1" ]; then
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" nginx_conf.ansible.yml
elif [ "$choice" == "2" ]; then
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" launch_script.ansible.yml
elif [ "$choice" == "3" ]; then
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" nginx_conf.ansible.yml
  ansible-playbook -i "$INVENTORY_FILE" --limit "$selected_server" -e "$ansible_extra_vars" launch_script.ansible.yml
else
  echo "Invalid choice. Exiting."
fi
