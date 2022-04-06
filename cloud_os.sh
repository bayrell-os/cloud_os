#!/bin/bash

SCRIPT_EXEC=$0
SCRIPT=$(readlink -f $0)
SCRIPT_PATH=`dirname $SCRIPT`

RETVAL=0
VERSION=0.1.0
TAG=`date '+%Y%m%d_%H%M%S'`


function generate {
	
	ENV_PATH=$SCRIPT_PATH/example/env.conf
	
	if [ ! -f $ENV_PATH ]; then
		
		if [ "$CLOUD_OS_KEY" = "" ]; then
			CLOUD_OS_KEY=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 128`
		fi
		
		if [ "$SSH_PASSWORD" = "" ]; then
			SSH_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#%^&*_\-+~' | head -c 16`
		fi
		
		if [ "$SSH_USER" = "" ]; then
			echo "Enter ssh username for Cloud OS:"
			read SSH_USER
		fi
		
		cat $SCRIPT_PATH/example/env.example > $ENV_PATH
		
		sed -i "s|CLOUD_OS_KEY=.*|CLOUD_OS_KEY=${CLOUD_OS_KEY}|g" $ENV_PATH
		sed -i "s|SSH_USER=.*|SSH_USER=${SSH_USER}|g" $ENV_PATH
		sed -i "s|SSH_PASSWORD=.*|SSH_PASSWORD=${SSH_PASSWORD}|g" $ENV_PATH
		
	fi
	
}

function output {
	
	ENV_PATH=$SCRIPT_PATH/example/env.conf
	
	if [ -f $ENV_PATH ]; then
		. $ENV_PATH
		echo "SSH_USER=${SSH_USER}"
		echo "SSH_PASSWORD=${SSH_PASSWORD}"
	else
		echo "Setup cloud os first"
	fi
}


case "$1" in
	
	download)
		docker pull bayrell/cloud_os_standard:0.4.0
	;;
	
	create_network)
		docker network create --subnet 172.21.0.1/16 --driver=overlay \
			--attachable cloud_network -o "com.docker.network.bridge.name"="cloud_network"
		
		sleep 2
		
		docker network ls
	;;
	
	generate)
		generate
	;;
	
	compose)
		docker-compose -f example/cloud_os.yaml -p "cloud_os" up -d
	;;
	
	output)
		output
	;;
	
	setup)
		$0 download
		$0 create_network
		$0 generate
		$0 compose
		$0 output
	;;
	
	*)
		echo "Usage: $SCRIPT_EXEC {setup|compose|output}"
		RETVAL=1

esac

exit $RETVAL