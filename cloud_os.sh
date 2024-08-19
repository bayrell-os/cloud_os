#!/bin/bash

SCRIPT_EXEC=$0
SCRIPT=$(readlink -f $0)
SCRIPT_PATH=`dirname $SCRIPT`

RETVAL=0
VERSION=0.5.1
TAG=`date '+%Y%m%d_%H%M%S'`
ENV_CONFIG_PATH=$SCRIPT_PATH/example/env.conf


function read_env_config()
{
	if [ -f "$ENV_CONFIG_PATH" ]; then
		while IFS= read -r line; do
			IFS="=" read -r left right <<< $line
			
			CMD="$left=\"$right\""
			if [ ! -z "$left" ]; then
				eval "$CMD"
			fi
		done < $ENV_CONFIG_PATH
	fi
}

function generate_env_config()
{
	if [ ! -f "$ENV_CONFIG_PATH" ]; then
		cat $SCRIPT_PATH/example/env.example > $ENV_CONFIG_PATH
	fi
	
	read_env_config
	
	if [ -z "$CLOUD_OS_KEY" ]; then
		CLOUD_OS_KEY=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 128`
		echo "CLOUD_OS_KEY=${CLOUD_OS_KEY}" >> $ENV_CONFIG_PATH
	fi
	
	if [ -z "$SSH_PASSWORD" ]; then
		SSH_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9!@%^*_\-+~' | head -c 16`
		echo "SSH_PASSWORD=${SSH_PASSWORD}" >> $ENV_CONFIG_PATH
	fi
	
	if [ -z "$SSH_USER" ]; then
		echo "Enter ssh username for Cloud OS:"
		read SSH_USER
		echo "SSH_USER=${SSH_USER}" >> $ENV_CONFIG_PATH
	fi
}

function print_env_config()
{
	if [ -f "$ENV_CONFIG_PATH" ]; then
		read_env_config
		echo "SSH_USER=${SSH_USER}"
		echo "SSH_PASSWORD=${SSH_PASSWORD}"
	else
		echo "Setup cloud os first"
	fi
}

function download_container()
{
	res=`docker images | grep cloud_os_standard | grep $VERSION`
	if [ ! -z "$res" ]; then
		return 1
	fi
	
	echo "Download cloud os v$VERSION"
	docker pull bayrell/cloud_os_standard:$VERSION
	
	if [ $? -ne 0 ]; then
		echo "Failed to download cloud os"
		exit 1
	fi
}

function apt_install()
{
	sudo apt-get update
	sudo apt-get install aptitude mc nano htop iftop bwm-ng iperf iperf3 iotop tmux screen python3-pip openntpd sshfs net-tools rsync jq
}

function create_swarm()
{
	res=`docker node ls > /dev/null 2>&1`
	if [ $? -ne 0 ]; then
		echo "Create docker swarm"
		docker swarm init
	fi
}

function create_network()
{
	res=`docker network ls | grep cloud_network`
	if [ -z "$res" ]; then
		echo "Create docker cloud network"
		docker network create --subnet 172.21.0.0/16 --driver=overlay \
			--attachable cloud_network -o "com.docker.network.bridge.name"="cloud_network"
	fi
}

function compose()
{
	echo "Compose cloud os"
	res=`docker ps -a |grep cloud_os_standard`
	if [ ! -z "$res" ]; then
		docker stop cloud_os_standard > /dev/null
		docker rm cloud_os_standard > /dev/null
	fi
	docker run -d \
		-p 8022:22 \
		-v cloud_os_standard:/data \
		-v /var/run/docker.sock:/var/run/docker.sock:ro \
		-v /etc/hostname:/etc/hostname_orig:ro \
		-e WWW_UID=1000 \
		-e WWW_GID=1000 \
		--name cloud_os_standard \
		--hostname cloud_os_standard.local \
		--env-file $SCRIPT_PATH/example/env.conf \
		--restart unless-stopped \
		--network cloud_network \
		bayrell/cloud_os_standard:$VERSION
}

function setup_json_config()
{
	config="{}"
	if [ -f /etc/docker/daemon.json ]; then
		config=`cat /etc/docker/daemon.json`
	fi
	
	# Change config
	config=`jq '. += { "log-driver": "json-file" }' <<< "$config"`
	config=`jq 'del(."log-opts")' <<< "$config"`
	#config=`jq '. += { "log-opts": {} }' <<< "$config"`
	config=`jq '."log-opts" += { "max-size": "10m" }' <<< "$config"`
	config=`jq '."log-opts" += { "max-file": "1" }' <<< "$config"`
	
	# Save file
	echo $config | jq . | sudo tee /etc/docker/daemon.json > /dev/null
	
	#cat /etc/docker/daemon.json
}

case "$1" in
	
	download)
		download_container
	;;
	
	create_network)
		create_network
		sleep 2
		docker network ls
	;;
	
	generate)
		generate_env_config
		print_env_config
	;;
	
	compose)
		generate_env_config
		compose
	;;
	
	output)
		print_env_config
	;;
	
	install)
		download_container
		setup_json_config
		create_swarm
		create_network
	;;
	
	setup)
		apt_install
		download_container
		setup_json_config
		create_swarm
		create_network
		generate_env_config
		compose
		print_env_config
	;;
	
	*)
		echo "Usage: $SCRIPT_EXEC {setup|compose}"
		RETVAL=1

esac

exit $RETVAL
