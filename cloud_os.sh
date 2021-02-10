#!/bin/bash

SCRIPT_EXEC=$0
SCRIPT=$(readlink -f $0)
SCRIPT_PATH=`dirname $SCRIPT`

RETVAL=0
VERSION=0.1.0
TAG=`date '+%Y%m%d_%H%M%S'`


function generate {
	
	ENV_PATH=$SCRIPT_PATH/example/env.conf
	CLOUD_KEY_PATH=$SCRIPT_PATH/example/cloud.key
	
	if [ ! -f $ENV_PATH ]; then
		
		CLOUD_KEY=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 128`
		CLOUD_MYSQL_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16`
		
		cat $SCRIPT_PATH/example/env.example > $ENV_PATH
		
		sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${CLOUD_MYSQL_PASSWORD}|g" $ENV_PATH
		sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${CLOUD_MYSQL_PASSWORD}|g" $ENV_PATH
		sed -i "s|CLOUD_KEY=.*|CLOUD_KEY=${CLOUD_KEY}|g" $ENV_PATH

		echo $CLOUD_KEY > $CLOUD_KEY_PATH
		
	fi
	
}


case "$1" in
	
	download)
		docker pull bayrell/alpine_mariadb:10.5-2
		docker pull rabbitmq:3.8.9-management
		docker pull bayrell/alpine_php_fpm:7.3-4
		docker pull bayrell/bus_gateway:0.3.0
		docker pull bayrell/cloud_os_standard:0.3.0
		docker pull bayrell/load_balancer_http:0.3.0
	;;
	
	create_network)
		docker network create --subnet 172.21.0.1/16 --driver=overlay --attachable cloud_frontend -o "com.docker.network.bridge.name"="cloud_frontend"
		
		docker network create --subnet 172.22.0.1/16 --driver=overlay --attachable cloud_backend -o "com.docker.network.bridge.name"="cloud_backend"
		
		sleep 2
		
		docker network ls
	;;
	
	generate)
		generate
	;;
	
	compose)
		docker stack deploy -c example/database.yaml database --with-registry-auth
		docker stack deploy -c example/cloud_os.yaml cloud_os --with-registry-auth
	;;
	
	setup)
		$0 download
		$0 create_network
		$0 generate
		$0 compose
	;;
	
	*)
		echo "Usage: $SCRIPT_EXEC setup"
		RETVAL=1

esac

exit $RETVAL