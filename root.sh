#!/usr/bin/env bash

KERNELNAME=$1
VERSION="$(make -s kernelversion)"
KERNELVERSION="${VERSION}-${KERNELNAME}"
KERNELDIR="/opt/kernel-sources/${KERNELVERSION}"
MODULESDIR="/lib/modules/${KERNELVERSION}/kernel/misc"
SIGNING_SCRIP="${KERNELDIR}/scripts/sign-file"
KEYPEM="${KERNELDIR}/certs/signing_key.pem"
KEYX509="${KERNELDIR}/certs/signing_key.x509"
PARTUUID="$(lsblk -no PARTUUID,MOUNTPOINT | grep -E " /$" | cut -d' ' -f1)"
configFound=1
cpuno=$(grep -Pc "processor\t:" /proc/cpuinfo)
cpuno=$(($cpuno + 1))

export CHOST="x86_64-pc-linux-gnu"
export CFLAGS="-march=native -O2 -pipe -msse3"
export CXXFLAGS="${CFLAGS}"

if [[ -z $KERNELNAME ]]; then
    >&2 echo "ERROR: a name for the kernel is needed"
    exit 2
fi

if [[ ! -d $KERNELDIR ]]; then
    >&2 echo "ERROR: $KERNELDIR doesn't exists"
    exit 2
fi

if [[ -d /usr/lib/modules/${KERNELVERSION} ]]; then
    echo "=>    Removing /usr/lib/modules/${KERNELVERSION}"
    rm -rf /usr/lib/modules/${KERNELVERSION}
fi

echo "=>    Installing Modules and Headers"
make -j $cpuno O=${KERNELDIR} modules_install headers_install
if [[ $? -ne 0 ]]; then
    >&2 echo "ERROR: Installing Modules and headers failed"
    exit 2
fi

rm -vf /boot/{Config-${KERNELVERSION},initramfs-${KERNELVERSION}.img,System.map,vmlinuz-${KERNELVERSION}}
cp -v $KERNELDIR/.config /boot/Config-${KERNELVERSION}
cp -v $KERNELDIR/System.map /boot/System.map
cp -v $KERNELDIR/arch/x86_64/boot/bzImage /boot/vmlinuz-${KERNELVERSION}
echo "=>    Creating iamge"
mkinitcpio -v -k ${KERNELVERSION} -g /boot/initramfs-${KERNELVERSION}.img

if [[ ! -f /boot/loader/entries/${KERNELVERSION}.conf ]]; then
    echo "=>    Creating entry file"
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


dkms remove vboxhost/5.1.26_OSE -k $KERNELVERSION
dkms install vboxhost/5.1.26_OSE -k $KERNELVERSION
if [[ $? -ne 0 ]]; then
    >&2 echo "ERROR: installing DKMS modules failed"
    exit 2
fi


if [[ ! -f $KEYPEM ]]; then
    >&2 echo "ERROR: ${KEYPEM} doesn't exists"
    exit 2
fi
if [[ ! -f $KEYX509 ]]; then
    >&2 echo "ERROR: ${$KEYX509} doesn't exists"
    exit 2
fi

$SIGNING_SCRIP sha1 $KEYPEM $KEYX509 $MODULESDIR/vboxdrv.ko
$SIGNING_SCRIP sha1 $KEYPEM $KEYX509 $MODULESDIR/vboxnetadp.ko
$SIGNING_SCRIP sha1 $KEYPEM $KEYX509 $MODULESDIR/vboxnetflt.ko
$SIGNING_SCRIP sha1 $KEYPEM $KEYX509 $MODULESDIR/vboxpci.ko

echo "=>    Bye!"
exit 0
