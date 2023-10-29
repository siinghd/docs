#!/bin/bash

ROOT_DIR=$(pwd)

sudo apt update

sudo apt install -y software-properties-common

sudo apt install -y git

sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

mkdir -p ~/envs ~/scripts ~/ansible ~/sites

cp $ROOT_DIR/ansible/server/set_nginx_conf.ansible.yml ~/ansible/
cp $ROOT_DIR/ansible/server/start_script_pnpm.ansible.yml ~/ansible/
cp $ROOT_DIR/ansible/server/start_script_yarn.ansible.yml ~/ansible/
cp $ROOT_DIR/ansible/server/provision_server.ansible.yml ~/ansible/

cp $ROOT_DIR/scripts/test.sh ~/scripts/start_script_v2.sh

cd ~/ansible

ansible-playbook provision_server.ansible.yml
