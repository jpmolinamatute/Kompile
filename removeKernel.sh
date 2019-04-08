#!/usr/bin/env bash

name="$1"
version="$2"

exitWithError() {
	local red='\033[0;31m'
	local end='\033[0m'
	echo -e "${red}ERROR: $1${end}" >&2
	exit 2
}

printLine() {
	local green='\033[1;32m'
	local end='\033[0m'
	echo -e "${green}==>    $1${end}"
}

if [[ $EUID -ne 0 ]]; then
	exitWithError "This script must be run as root"
fi

if [[ -z $name || -z $version ]]; then
	exitWithError "Please provide a name and a version"
fi

list=("/boot/config-${version}-${name}" "/boot/initramfs-${version}-${name}.img" "/boot/System.map" "/boot/vmlinuz-${version}-${name}" "/usr/lib/modules/${version}-${name}" "/boot/loader/entries/${version}-${name}.conf")

for i in "${list[@]}"; do
	if [[ -f $i ]]; then
		rm "$i"
	fi
done

if [[ -d /usr/src/linux-${version} ]]; then
	printLine "Do you want to remove /usr/src/linux-${version}"
	read -r answer
	if [[ $answer =~ ^[yY] ]]; then
		rm -rf "/usr/src/linux-${version}"
	fi
fi

printLine "Bye!"
exit 0
