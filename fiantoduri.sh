#!/bin/bash
########## Info ##########
# Backup Fortinet Router Config

# This script allow you to create Fortinet configs backups,download,rotate, cipher and
# upload them to github or artifactory repository. Using a HOPPER to connect to the Frotinet Server.
#Code by: jjavieralv
# Version: 0.1v

######### GLOBAL VARIABLES #########

#Dependencies
DEPENDENCIES=(ssh expect netcat zip openssl)




######### INDIVIDUAL FUNCTIONS #########

##### DECLARE CONFIG VARIABLES #####
function variables_github(){
	# GitHub variables
	GITHUB_REPO=
	GITHUB_USER=
	GITHUB_MAIL=
	GITHUB_KEY_ROUTE=
	GITHUB_KEY_PASS=
}

function variables_cipher(){
	# Cipher config
	## use symetric(0) or asymetric(with pass(default))(1)
	CIPHER_TYPE=0
	CYPHER_SYMETRIC_PASS=
	## if you want to use an asymetric pass
	CIPHER_ASYMETRIC_KEY_ROUTE=
	CIPHER_ASYMETRIC_KEY_PASS=
}

function variables_fortinet(){
	#Fortinet values
	FORTINET_USER=
	## use pass(0) or use private key(with pass)(1)
	FORTINET_ACCESS_METHOD=0
	FORTINET_PASS=
	FORTINET_KEY_ROUTE=
	FORTINET_KEY_PASS=
	FORTINET_IP=
	FORTINET_PORT=
	FORTINET_CONFIG_ROUTE=
}

function variables_hopper(){
	#HOPPER credentials
	HOPPER_IP=
	HOPPER_SSH_PORT=
	HOPPER_LOCAL_PORT=
	HOPPER_USER=
	HOPPER_PASS=
	HOPPER_KEY_ROUTE=
	HOPPER_KEY_PASS=
}

function variables_general(){
	LOCAL_CONFIG_FORTI_ROUTE=
}

##### GRAPHICAL FUNCTIONS #####
	function red_messages() {
	  #crittical and error messages
	  echo -e "\033[31m$1\e[0m"
	}

	function green_messages() {
	  #starting functions and OK messages
	  echo -e "\033[32m$1\e[0m"
	}

	function magenta_messages(){
	  #what part which is executting
	  echo -e "\e[45m$1\e[0m"
	}

#### CONNECTIVITY FUNCTIONS #####
function install_dependencies(){
	echo -e "Installing $1"
	sudo apt install "$1" -y
	if [[ $? -eq 0 ]];then
		green_messages "$1 installed correctly"
	else
		red_messages "Not able to install $1. Exiting"
		exit 20
	fi
}

function check_dependencies(){
	echo -e "\n"
	magenta_messages "### Checking dependencies ###"
	for i in ${DEPENDENCIES[@]}; do
		which $i >/dev/null
		if [[ $? -eq 0 ]];then
			green_messages " $i is installed "
		else
			red_messages "$i is not installed"
			install_dependencies "$i"
		fi
	done
}

function create_ssh_tunel(){
	# $1 localport to be redirected
	# $2 fortinet IP 
	# $3 fortinet ssh PORT
	# $4 HOPPER USER
	# $5 HOPPER IP
	# $6 HOPPER PORT
	# FIRST YOU MUST ADD YOUR SSHCERT 
	echo -e "\n"
	magenta_messages "### Starting SSH tunel ###"
	# starting the tunnel (if no other process uses the tunel in 10s,
	# closes automatically)
	ssh -o "StrictHostKeyChecking no" -L $1:$2:$3 -f $4@$5 -p $6 sleep 10
	echo aaaa
}

function add_ssh_key(){
	# $1	SSH key route
	# $2	SSH key pass
	echo -e "\n"
	magenta_messages "### Add private ssh key ###"
	echo "ROUTE: $1"
	eval `ssh-agent -s`

	expect << EOF
	  spawn ssh-add $1
	  expect "Enter passphrase"
	  send "$2\r"
	  expect eof
EOF
}

function check_connectivity(){
	#Wait an array with the ip and port whitespaced. Ej: check_connectivity "ip1 port1" "ip2 port2" 
	echo -e "\n"
	magenta_messages "### Checking connectivity ###"
	for i in "$@";do
		echo "Checking connectivity with: $i"
		nc -z -v "${i% *}" "${i#* }"
		if [[ $? -ne 0 ]];then
			red_messages "No connectivity with $i. Exiting"
			exit
		fi
		shift
	done
}

function download_file_scp(){
	# $1	pass type (0 symetric 1 asymetric)
	# $2	server port
	# $3	server user
	# $4	server ip
	# $5	server file route
	# $6	local route to download

	echo -e "\n"
	magenta_messages "### Download Forti Backup ###"

	if [[ $1 -eq 0 ]];then
		echo "parsing ssh user pass"
		expect << EOF
		spawn scp -P ${2} ${3}@${4}:${5} ${6}
		expect {
    		"continue" { send "yes\n"; exp_continue }
    		"assword:" { send "${7}\n"; }
		}
		expect eof
EOF
		if [[ $? -ne 0 ]];then
			red_messages "Something went wrong with scp. Exiting"
			exit 30
		fi
	else
		echo "using asymetric pass(must be added before)"
		expect << EOF
		spawn scp -P ${2} ${3}@${4}:${5} ${6}
		expect {
    		"continue" { send "yes\n"; exp_continue }
    		"assword:" { echo "something went wrong with asymetric authentication" }
		}
		expect eof
EOF
	fi
	
	if [[ $? -ne 0 ]];then
		red_messages "Something went wrong with scp. Exiting"
		exit 30
	fi
}

function fortinet_generate_backup_name(){
	# $1	Backup file
	echo -e "\n"
	magenta_messages "### Generate fortinet backup name ###"
	CONF_FILE_NAME="$(date '+%Y/%m/%d_%H:%M')"
	CONF_FILE_NAME="${CONF_FILE_NAME}_$(grep conf_file_ver ${1}|cut -d'=' -f2)"
}

function zip_file(){
	# $1	File route
	# $2	New file zip
	echo -e "\n"
	magenta_messages "### Zip file ###"
	zip -9rm "${2}" "${1}" 
	if [[ $? -ne 0 ]];then
		red_messages "Error ocurred zip file. Exiting"
		exit 40
	fi
}

######### AGREGATED FUNCTIONS #########
function checking_all_before_start(){
	magenta_messages "\n ######### Checking all before start #########"
	check_dependencies
	check_connectivity "$HOPPER_IP $HOPPER_SSH_PORT" 
}

function tunneling_hopper(){
	magenta_messages "\n ######### Tunneling hopper #########"
	add_ssh_key $HOPPER_KEY_ROUTE $HOPPER_KEY_PASS
	create_ssh_tunel "$HOPPER_LOCAL_PORT" "$FORTINET_IP" "$FORTINET_PORT" "$HOPPER_USER" "$HOPPER_IP" "$HOPPER_SSH_PORT"
}

function fortinet_get_backup(){
	magenta_messages "\n ######### Getting Forti Backup #########"
	check_connectivity "localhost $HOPPER_LOCAL_PORT"
	download_file_scp ${FORTINET_ACCESS_METHOD} ${HOPPER_LOCAL_PORT} ${FORTINET_USER} 'localhost' ${FORTINET_CONFIG_ROUTE} ${LOCAL_CONFIG_FORTI_ROUTE} ${FORTINET_PASS}
}

function fortinet_manage_backup(){
	magenta_messages "\n ######### Modify backup #########"
	fortinet_generate_backup_name "${LOCAL_CONFIG_FORTI_ROUTE}"
	CONF_FILE_NAME_ZIP="${CONF_FILE_NAME}".zip
	zip_file "${LOCAL_CONFIG_FORTI_ROUTE}" "${CONF_FILE_NAME_ZIP}"
	
	cypher_file "${CIPHER_TYPE}" "${CONF_FILE_NAME_ZIP}" "${CIPHER_ASYMETRIC_KEY_ROUTE}"
}

 
######### MAIN #########
function main(){
	#initialize variables
	variables_hopper
	variables_fortinet
	variables_general

	checking_all_before_start
	tunneling_hopper
	fortinet_get_backup
	fortinet_manage_backup

	
	
	echo "el estado ha sido $?"
}

main