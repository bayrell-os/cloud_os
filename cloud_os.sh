#!/bin/bash

SCRIPT_EXEC=$0
SCRIPT=$(readlink -f $0)
SCRIPT_PATH=`dirname $SCRIPT`

VERSION=$1
VERSION_LATEST="0.5.1"
ENV_CONFIG_PATH=/etc/cloudos.conf
ENABLE_IPTABLES=1
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
APT_UPDATED=0

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
	
	if [ -z "$VERSION" ] && [ ! -z "$CLOUD_OS_VERSION" ]; then
		VERSION=$CLOUD_OS_VERSION
	fi
	
	if [ -z "$VERSION" ] && [ ! -z "$VERSION_LATEST" ]; then
		VERSION=$VERSION_LATEST
	fi
	
	ADMIN_USERNAME=$SSH_USER
	ADMIN_PASSWORD=$SSH_PASSWORD
}

function generate_env_config()
{
	if [ -z "$CLOUD_OS_KEY" ]; then
		CLOUD_OS_KEY=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 128`
	fi
	
	if [ -z "$ADMIN_PASSWORD" ]; then
		ADMIN_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9!@%^*_\-+~' | head -c 16`
	fi
	
	if [ -z "$ADMIN_USERNAME" ]; then
		ADMIN_USERNAME="admin"
	fi
	
	local text=""
	text="${text}NODE_ID={{.Node.ID}}\n"
	text="${text}TASK_ID={{.Task.ID}}\n"
	text="${text}SERVICE_ID={{.Service.ID}}\n"
	text="${text}CLOUD_OS_GATEWAY=cloud_os_standard_1\n"
	text="${text}CLOUD_OS_KEY=${CLOUD_OS_KEY}\n"
	text="${text}CLOUD_OS_VERSION=${VERSION}\n"
	text="${text}SSH_USER=${ADMIN_USERNAME}\n"
	text="${text}SSH_PASSWORD=${ADMIN_PASSWORD}\n"
	echo -e $text | sudo tee $ENV_CONFIG_PATH > /dev/null
}

function setup_admin_name()
{
	local text=$(whiptail --title "Type username" \
		--inputbox "Enter ssh username for Cloud OS" 8 39 3>&1 1>&2 2>&3)
	
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	if [ -z "$text" ]; then
		return 1
	fi
	
	ADMIN_USERNAME=$text
	return 0
}

function setup_admin_password()
{
	local text=$(whiptail --title "Type password" \
		--inputbox "Enter ssh password for Cloud OS" 8 39 3>&1 1>&2 2>&3)
	
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	if [ -z "$text" ]; then
		return 1
	fi
	
	ADMIN_PASSWORD=$text
	return 0
}

function change_username()
{
	setup_admin_name
	if [ $? -eq 0 ]; then
		generate_env_config
	fi
}

function change_password()
{
	setup_admin_password
	if [ $? -eq 0 ]; then
		generate_env_config
	fi
}

function print_env_config()
{
	if [ -f "$ENV_CONFIG_PATH" ]; then
		read_env_config
		echo "Cloud OS ${VERSION}"
		echo "SSH_USER=${SSH_USER}"
		echo "SSH_PASSWORD=${SSH_PASSWORD}"
	else
		echo "Setup cloud os first"
	fi
}

function download_container()
{
	local res=`sudo docker images | grep cloud_os_standard | grep $VERSION`
	if [ ! -z "$res" ]; then
		return 1
	fi
	
	echo "Download cloud os v$VERSION"
	sudo docker pull bayrell/cloud_os_standard:$VERSION
	
	if [ $? -ne 0 ]; then
		echo "Failed to download cloud os"
		exit 1
	fi
}

function apt_update()
{
	if [ "$APT_UPDATED" = "0" ]; then
		sudo apt-get update
		if [ $? -ne 0 ]; then
			echo "Failed to update apt"
			exit 1
		fi
		APT_UPDATED=1
	fi
}

function install_jq()
{
	local res=`whereis jq | grep bin`
	if [ -z "$res" ]; then
		apt_update
		sudo apt-get install -y jq
		if [ $? -ne 0 ]; then
			echo "Failed to install jq"
			exit 1
		fi
	fi
}

function install_iptables()
{
	if [ ! -d /etc/iptables ]; then
		sudo mkdir /etc/iptables
	fi
	if [ ! -f /etc/iptables/rules.v4 ]; then
		echo "Install iptables"
		local text=""
		text="${text}*filter\n"
		text="${text}:INPUT ACCEPT [0:0]\n"
		text="${text}:FORWARD ACCEPT [0:0]\n"
		text="${text}:OUTPUT ACCEPT [0:0]\n"
		text="${text}-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT\n"
		text="${text}-A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT\n"
		text="${text}-A INPUT -p icmp -j ACCEPT\n"
		text="${text}-A INPUT -i lo -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m tcp --dport 2376 -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m tcp --dport 2377 -j ACCEPT\n"
		text="${text}-A INPUT -p tcp -m tcp --dport 7946 -j ACCEPT\n"
		text="${text}-A INPUT -p udp -m udp --dport 7946 -j ACCEPT\n"
		text="${text}-A INPUT -p udp -m udp --dport 4789 -j ACCEPT\n"
		text="${text}-A INPUT -i docker0 -p udp -m udp --dport 53 -j ACCEPT\n"
		text="${text}-A INPUT -i docker0 -p tcp -m tcp --dport 53 -j ACCEPT\n"
		text="${text}-A INPUT -i docker_gwbridge -p udp -m udp --dport 53 -j ACCEPT\n"
		text="${text}-A INPUT -i docker_gwbridge -p tcp -m tcp --dport 53 -j ACCEPT\n"
		text="${text}-A INPUT -j REJECT\n"
		text="${text}-A FORWARD -j REJECT\n"
		text="${text}COMMIT\n"
		echo -e $text | sudo tee /etc/iptables/rules.v4 > /dev/null
		sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v6
	fi
	local res=`whereis iptables | grep bin`
	if [ -z "$res" ]; then
		apt_update
		sudo DEBIAN_FRONTEND='noninteractive' apt-get install -y iptables-persistent
		if [ $? -ne 0 ]; then
			echo "Failed to install iptables"
			exit 1
		fi
	fi
}

function install_docker()
{
	local res=`whereis docker | grep bin`
	if [ -z "$res" ]; then
		echo "Install docker"
		apt_update
		sudo apt-get install -y docker.io
		if [ $? -ne 0 ]; then
			echo "Failed to install docker"
			exit 1
		fi
	fi
}

function create_swarm()
{
	local res=`sudo docker node ls 2>&1 > /dev/null`
	res=`echo $res | grep "docker swarm init"`
	if [ ! -z "$res" ]; then
		echo "Create docker swarm"
		sudo docker swarm init
		if [ $? -ne 0 ]; then
			echo "Failed to create docker swarm"
			exit 1
		fi
	fi
}

function create_network()
{
	local res=`sudo docker network ls | grep cloud_network 2>/dev/null`
	if [ -z "$res" ]; then
		echo "Create docker cloud network"
		sudo docker network create --subnet 172.21.0.0/16 --driver=overlay \
			--attachable cloud_network -o "com.docker.network.bridge.name"="cloud_network"
		if [ $? -ne 0 ]; then
			echo "Failed to create docker network"
			exit 1
		fi
	fi
}

function compose()
{
	echo "Compose Cloud OS"
	local res=`sudo docker ps -a |grep cloud_os_standard`
	if [ ! -z "$res" ]; then
		sudo docker stop cloud_os_standard > /dev/null
		sudo docker rm cloud_os_standard > /dev/null
	fi
	sudo docker run -d \
		-p 8022:22 \
		-v cloud_os_standard:/data \
		-v /var/run/docker.sock:/var/run/docker.sock:ro \
		-v /etc/hostname:/etc/hostname_orig:ro \
		-e WWW_UID=1000 \
		-e WWW_GID=1000 \
		--name cloud_os_standard \
		--hostname cloud_os_standard.local \
		--env-file $ENV_CONFIG_PATH \
		--restart unless-stopped \
		--network cloud_network \
		bayrell/cloud_os_standard:$VERSION
	if [ $? -ne 0 ]; then
		echo "Failed to compose cloud os"
		exit 1
	fi
}

function setup_locale()
{
	if [ ! -f "/etc/profile.d/0.locale.sh" ]; then
		local text=""
		text="${text}export LANG=\"en_US.UTF-8\"\n"
		text="${text}export LANGUAGE=\"en_US:en\"\n"
		text="${text}export LC_CTYPE=\"en_US.UTF-8\"\n"
		text="${text}export LC_NUMERIC=\"en_US.UTF-8\"\n"
		text="${text}export LC_TIME=\"en_US.UTF-8\"\n"
		text="${text}export LC_COLLATE=\"en_US.UTF-8\"\n"
		text="${text}export LC_MONETARY=\"en_US.UTF-8\"\n"
		text="${text}export LC_MESSAGES=\"en_US.UTF-8\"\n"
		text="${text}export LC_PAPER=\"en_US.UTF-8\"\n"
		text="${text}export LC_NAME=\"en_US.UTF-8\"\n"
		text="${text}export LC_ADDRESS=\"en_US.UTF-8\"\n"
		text="${text}export LC_TELEPHONE=\"en_US.UTF-8\"\n"
		text="${text}export LC_MEASUREMENT=\"en_US.UTF-8\"\n"
		text="${text}export LC_IDENTIFICATION=\"en_US.UTF-8\"\n"
		echo -e $text | sudo tee /etc/profile.d/0.locale.sh > /dev/null
	fi
	
	local res=0
	local generate_locale=0
	
	res=`cat /etc/locale.gen | grep "^en_US.UTF-8 UTF-8"`
	if [ -z "$res" ]; then
		echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
		generate_locale=1
	fi
	
	res=`cat /etc/locale.gen | grep "^ru_RU.UTF-8 UTF-8"`
	if [ -z "$res" ]; then
		echo "ru_RU.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
		generate_locale=1
	fi
	
	if [ $generate_locale -eq 1 ]; then
		echo "Setup locale"
		sudo locale-gen
		if [ $? -ne 0 ]; then
			echo "Failed to generate locale"
			exit 1
		fi
	fi
}

function setup_journald_config()
{
	local res=`cat /etc/systemd/journald.conf | grep ^SystemMaxUse`
	if [ -z "$res" ]; then
		echo "SystemMaxUse=10G" | sudo tee -a /etc/systemd/journald.conf > /dev/null
	fi
}

function setup_docker_config()
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
}

function setup_crontab()
{
	local text=`sudo crontab -l -u root 2>/dev/null`
	local update=0
	local res=""
	
	res=`echo $text | grep "docker system prune"`
	if [ -z "$res" ]; then
		text="${text}0 */2 * * * docker system prune --filter \"until=24h\" -f -a > /dev/null 2>&1\n"
		update=1
	fi
	
	res=`echo $text | grep "docker image prune"`
	if [ -z "$res" ]; then
		text="${text}0 */2 * * * docker image prune --filter \"until=24h\" -f -a > /dev/null 2>&1\n"
		update=1
	fi
	
	if [ $update -eq 1 ]; then
		echo -e "$text" | sudo crontab -u root -
	fi
}

function init()
{
	setup_locale
	setup_journald_config
	setup_crontab
	install_jq
	install_iptables
	install_docker
	setup_docker_config
	create_swarm
	create_network
}

function run_installer()
{
	init
	generate_env_config
	download_container
	compose
	print_env_config
}

function show_setup()
{
	local text=""
	text="${text}Version: $VERSION\n"
	text="${text}\n"
	text="${text}The installer will do:\n"
	text="${text}1) Setup en locale\n"
	text="${text}2) Setup journald\n"
	text="${text}3) Setup iptables\n"
	text="${text}4) Create Docker swarm\n"
	text="${text}5) Compose cloud os container\n"
	text="${text}\n"
	text="${text}Do you want to run installer?\n"
	whiptail --title "BAYRELL Cloud OS installer" --yesno "$text" 20 60
	
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	if [ -z "$ADMIN_USERNAME" ]; then
		setup_admin_name
	fi
	
	if [ -z "$ADMIN_USERNAME" ]; then
		return 1
	fi
	
	echo "Run installer"
	echo "Install Cloud OS $VERSION"
	run_installer
	
	return 0
}

function show_menu()
{
	local item=$(whiptail --title "BAYRELL Cloud OS installer" --menu "Chose option:" 15 60 6 \
		"setup" "Install OS" \
		"username" "Change username" \
		"password" "Change password" \
		"compose" "Compose docker container" \
		"print" "Print config" \
		"exit" "Exit" 3>&1 1>&2 2>&3)
	
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	if [ "$item" = "setup" ]; then
		show_setup
		return 1
	fi
	
	if [ "$item" = "username" ]; then
		change_username
		return 0
	fi
	
	if [ "$item" = "password" ]; then
		change_password
		return 0
	fi
	
	if [ "$item" = "compose" ]; then
		generate_env_config
		compose
		return 1
	fi
	
	if [ "$item" = "print" ]; then
		print_env_config
		return 1
	fi
	
	if [ "$item" = "exit" ]; then
		return 1
	fi
	
	return 1
}

read_env_config

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
	
	print)
		print_env_config
	;;
	
	init)
		init
	;;
	
	install|setup)
		run_installer
	;;
	
	help)
		echo "Usage: $SCRIPT_EXEC {setup|compose|print}"
		exit 1
	;;
	
	*)
		while true; do
			show_menu
			if [ $? -ne 0 ]; then
				exit 0
			fi
		done

esac

exit 0
