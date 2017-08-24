#!/usr/bin/env bash

KERNELNAME="$1"
KERNELDIR="$2"
VERSION="$(make -s kernelversion)"
KERNELVERSION="${VERSION}-${KERNELNAME}"
MODULESDIR="/lib/modules/${KERNELVERSION}/kernel/misc"
SIGNING_SCRIP="${KERNELDIR}/scripts/sign-file"
KEYPEM="${KERNELDIR}/certs/signing_key.pem"
KEYX509="${KERNELDIR}/certs/signing_key.x509"
PARTUUID="$(lsblk -no PARTUUID,MOUNTPOINT | grep -E " /$" | cut -d' ' -f1)"
configFound=1
cpuno=$(grep -Pc "processor\t:" /proc/cpuinfo)
cpuno=$(($cpuno + 1))
unalias ls 2> /dev/null
vBoxVersion="$(ls -d /usr/src/vboxhost-* | cut -d'-' -f2)"
vBoxModules=("vboxdrv.ko" "vboxnetadp.ko" "vboxnetflt.ko" "vboxpci.ko")

export CHOST="x86_64-pc-linux-gnu"
export CFLAGS="-march=native -O2 -pipe -msse3"
export CXXFLAGS="${CFLAGS}"

exitWithError () {
    local COLOR='\033[0;31m'
    local NC='\033[0m'
    echo -e "${COLOR}$1${NC}"
    exit 2
}

printLine (){
    local COLOR='\033[1;32m'
    local NC='\033[0m'
    echo -e "${COLOR}=>    $1${NC}"
}

if [[ -z $KERNELNAME ]]; then
    exitWithError "ERROR: a name for the kernel is needed"
fi

if [[ ! -d $KERNELDIR ]]; then
    exitWithError "ERROR: $KERNELDIR doesn't exists"
fi

printLine "Removing config-${KERNELVERSION}, initramfs-${KERNELVERSION}.img, System.map, vmlinuz-${KERNELVERSION}"
rm -f /boot/{config-${KERNELVERSION},initramfs-${KERNELVERSION}.img,System.map,vmlinuz-${KERNELVERSION}}

if [[ -d /usr/lib/modules/${KERNELVERSION} ]]; then
    printLine "Removing /usr/lib/modules/${KERNELVERSION} directory"
    rm -rf /usr/lib/modules/${KERNELVERSION}
fi

printLine "Installing Modules and Headers"
make -j $cpuno O=${KERNELDIR} modules_install headers_install 1> /dev/null 2>> ${KERNELDIR}/Error
if [[ $? -ne 0 ]]; then
    exitWithError "ERROR: Installing Modules and headers failed"
fi
ls -Alh /lib/modules/4.12.8-ichigo

printLine "Copying $KERNELDIR/.config -> /boot/config-${KERNELVERSION}"
cp $KERNELDIR/.config /boot/config-${KERNELVERSION}

printLine "Copying $KERNELDIR/System.map -> /boot/System.map"
cp $KERNELDIR/System.map /boot/System.map

printLine "$KERNELDIR/arch/x86_64/boot/bzImage -> /boot/vmlinuz-${KERNELVERSION}"
cp $KERNELDIR/arch/x86_64/boot/bzImage /boot/vmlinuz-${KERNELVERSION}

printLine "Creating initramfs-${KERNELVERSION}.img file"
mkinitcpio -k ${KERNELVERSION} -g /boot/initramfs-${KERNELVERSION}.img
if [[ $? -ne 0 ]]; then
    exitWithError "ERROR: mkinitcpio failed"
fi

if [[ ! -f /boot/loader/entries/${KERNELVERSION}.conf ]]; then
    printLine "Creating entry file"
    (
    cat <<EOF
title Arch Linux
linux /vmlinuz-${KERNELVERSION}
version ${KERNELVERSION}
initrd /intel-ucode.img
initrd /initramfs-${KERNELVERSION}.img
options rootfstype=ext4 root=PARTUUID=${PARTUUID} rw
EOF
    ) > /boot/loader/entries/${KERNELVERSION}.conf
fi

printLine "Uninstalling old version of vboxhost/${vBoxVersion}"
dkms uninstall vboxhost/${vBoxVersion} -k $KERNELVERSION
printLine "Removing old version of vboxhost/${vBoxVersion}"
dkms remove vboxhost/${vBoxVersion} -k $KERNELVERSION

printLine "Building new version of vboxhost/${vBoxVersion}"
dkms build vboxhost/${vBoxVersion} -k $KERNELVERSION

printLine "Installing new version of vboxhost/${vBoxVersion}"
dkms install vboxhost/${vBoxVersion} -k $KERNELVERSION
if [[ $? -ne 0 ]]; then
    exitWithError "ERROR: installing DKMS modules failed"
fi

if [[ ! -f $KEYPEM ]]; then
    exitWithError "ERROR: ${KEYPEM} doesn't exists"
fi
if [[ ! -f $KEYX509 ]]; then
    exitWithError "ERROR: ${$KEYX509} doesn't exists"
fi

for module in "${vBoxModules[@]}"; do
    if [[ -f ${MODULESDIR}/${module} ]]; then
        printLine "Signing module $module"
        $SIGNING_SCRIP sha1 $KEYPEM $KEYX509 ${MODULESDIR}/${module}
    else
        exitWithError "ERROR: ${MODULESDIR}/${module} doesn't exists"
    fi
done

printLine "Bye!"
exit 0
