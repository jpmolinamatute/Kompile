#!/usr/bin/env bash

KERNELNAME=$1
VERSION="$(make -s kernelversion)"
KERNELVERSION="${VERSION}-${KERNELNAME}"
KERNELDIR="/opt/kernel-sources/${KERNELVERSION}"
MODULESDIR="/lib/modules/${KERNELVERSION}/kernel/misc"
configFound=1

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
make -j5 O=${KERNELDIR} modules_install headers_install
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
options rootfstype=ext4 root=PARTUUID=5189f326-0d28-4566-8a15-b3e5f5fea0cd rw
EOF
    ) > /boot/loader/entries/${KERNELVERSION}.conf
fi

dkms remove vboxhost/5.1.22_OSE -k $KERNELVERSION
if [[ $? -ne 0 ]]; then
    >&2 echo "ERROR: Removing DKMS modules failed"
    exit 2
fi
dkms install vboxhost/5.1.24_OSE -k $KERNELVERSION
if [[ $? -ne 0 ]]; then
    >&2 echo "ERROR: installing DKMS modules faile"d
    exit 2
fi

cd ${KERNELDIR}
./scripts/sign-file sha1 ./certs/signing_key.pem ./certs/signing_key.x509 $MODULESDIR/vboxdrv.ko
./scripts/sign-file sha1 ./certs/signing_key.pem ./certs/signing_key.x509 $MODULESDIR/vboxnetadp.ko
./scripts/sign-file sha1 ./certs/signing_key.pem ./certs/signing_key.x509 $MODULESDIR/vboxnetflt.ko
./scripts/sign-file sha1 ./certs/signing_key.pem ./certs/signing_key.x509 $MODULESDIR/vboxpci.ko

echo "=>    Bye!"
exit 0
