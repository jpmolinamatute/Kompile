#!/usr/bin/env bash

KERNELNAME=$1
KERNELNAME=${KERNELNAME:-"unknown"}
VERSION="$(make -s kernelversion)"
KERNELVERSION="${VERSION}-${KERNELNAME}"
KERNELDIR="/opt/kernel-sources/${KERNELVERSION}"
configFound=1

export CHOST="x86_64-pc-linux-gnu"
export CFLAGS="-march=native -O2 -pipe -msse3"
export CXXFLAGS="${CFLAGS}"

if [[ ! -d $KERNELDIR ]]; then
    >&2 echo "ERROR: $KERNELDIR doesn't exists"
    exit 2
fi

if [[ -d /usr/lib/modules/${KERNELVERSION} ]]; then
    echo "=>    Removing /usr/lib/modules/${KERNELVERSION}"
    rm -rf /usr/lib/modules/${KERNELVERSION}
fi

echo "=>    Installing Modules and Headers"
make -j5 O=${KERNELDIR} modules_install headers_install
if [[ $? -ne 0 ]]; then
    >&2 echo "ERROR: Installing Modules and headers failed"
    exit 2
fi
echo "=>    Removing /boot/{Config-${KERNELVERSION},initramfs-${KERNELVERSION}.img,System.map,vmlinuz-${KERNELVERSION}}"
rm -f /boot/{Config-${KERNELVERSION},initramfs-${KERNELVERSION}.img,System.map,vmlinuz-${KERNELVERSION}}

cp -v $KERNELDIR/.config /boot/Config-${KERNELVERSION}
cp -v $KERNELDIR/System.map /boot/System.map
cp -v $KERNELDIR/arch/x86_64/boot/bzImage /boot/vmlinuz-${KERNELVERSION}
echo "=>    Creating iamge"
mkinitcpio -v -k ${KERNELVERSION} -g /boot/initramfs-${KERNELVERSION}.img
echo "=>    Creating entry file"
(
cat <<EOF
title Arch Linux
linux /vmlinuz-${KERNELVERSION}
version ${KERNELVERSION}
initrd /intel-ucode.img
initrd /initramfs-${KERNELVERSION}.img
options rootfstype=ext4 root=PARTUUID=5189f326-0d28-4566-8a15-b3e5f5fea0cd rw
EOF
) > /boot/loader/entries/${KERNELVERSION}.conf
echo "=>    Bye!"
exit 0
