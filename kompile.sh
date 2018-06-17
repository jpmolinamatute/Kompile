#!/usr/bin/env bash

KERNELNAME="ichigo"
SOURCESDIR="/usr/src/linux-4.17"
BASEBUILDDIR="/opt/kernel-builds"
TEMPLATEFILE="/opt/kernel-builds/4.17.0-ichigo-4/.config"
EDITCONFIG=1
ONDONE="/home/juanpa/Projects/compile/external"

cpuno=$(grep -Pc "processor\\t:" /proc/cpuinfo)
FULLKERNELNAME=
KERNELVERSION=
BUILDDIR=
CONFIGFILE=
TEMPLATEVERSION=
MODULESDIR=
TRACKVERSION=

vercomp() {
    # FROM https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash
    # thanks Dennis Williamson
    if [[ $1 == "$2" ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

exitWithError() {
    local COLOR='\033[0;31m'
    local NC='\033[0m'
    echo -e >&2 "${COLOR}ERROR: $1${NC}"
    if [[ -f ${BUILDDIR}/Error ]]; then
        cat ${BUILDDIR}/Error
    fi
    exit 2
}

printLine() {
    local COLOR='\033[1;32m'
    local NC='\033[0m'
    echo -e "${COLOR}==>    $1${NC}"
}

checkDirectory() {
    local dir=$1
    if [[ -z $dir || ! -d $dir || ! -w $dir ]]; then
        exitWithError "Directory $dir doesn't exists or it's not writable"
    fi
}

checkSystem(){
    if [[ $EUID -ne 0 ]]; then
        exitWithError "This script must be run as root"
    fi
    command -v bc &> /dev/null
    if [[ $? -ne 0 ]]; then
        exitWithError "Please install bc"
    fi

    if [[ -z $KERNELNAME ]]; then
        exitWithError "Please provide a name"
    fi

    checkDirectory $SOURCESDIR
    checkDirectory $BASEBUILDDIR
}


getVersionSources() {
    KERNELVERSION="$(make -s kernelversion 2> /dev/null)"
}

setVariables() {
    if [[ -z $TRACKVERSION ]]; then
        FULLKERNELNAME="${KERNELVERSION}-${KERNELNAME}"
    else
        FULLKERNELNAME="${KERNELVERSION}-${KERNELNAME}-${TRACKVERSION}"
    fi
    BUILDDIR="${BASEBUILDDIR}/${FULLKERNELNAME}"
    CONFIGFILE="${BUILDDIR}/.config"
    MODULESDIR="/usr/lib/modules/${FULLKERNELNAME}"
}

getTemplateVersion() {
    TEMPLATEVERSION="$(grep -E "# Linux/x86 [0-9.-]* Kernel Configuration" "$CONFIGFILE" | cut -d' ' -f3 | cut -d'-' -f1)"
}

setbuilddir() {
    if [[ -d $BUILDDIR ]]; then
        printLine "A Kernel ${KERNELNAME} was found!. Do you want to Replace it or Increment it (r, i)"
        read -r answer

        if [[ $answer =~ [iI] ]]; then
            local FILES="${BUILDDIR}*"
            for f in $FILES
            do
                TRACKVERSION=$(cut -d'-' -f4 <<<"$f")
            done

            if [[ -z $TRACKVERSION ]]; then
                TRACKVERSION=1
            else
                TRACKVERSION=$((TRACKVERSION+1))
            fi

            setVariables
            printLine "mkdir ${BUILDDIR}"
            mkdir "$BUILDDIR"
        fi
    else
        printLine "mkdir ${BUILDDIR}"
        mkdir "$BUILDDIR"
    fi
    printLine "make -j $cpuno O=$BUILDDIR distclean"
    make -j "$cpuno" V=0 O="$BUILDDIR" distclean 2> "${BUILDDIR}/Error" 1> /dev/null
    echo "#####  Error log start here  #####" > "${BUILDDIR}/Error"
}

moveTemplate(){
    if [[ -f $TEMPLATEFILE ]]; then
        printLine "Config file found: $TEMPLATEFILE"
        cp "$TEMPLATEFILE" "$CONFIGFILE"
        chmod 644 "$CONFIGFILE"
    else
        command -v zcat &> /dev/null
        if [[ $? -eq 0 &&  -f /proc/config.gz ]]; then
            printLine "zcat /proc/config.gz > ${CONFIGFILE}"
            zcat /proc/config.gz > "$CONFIGFILE"
        # elif [[ -f /boot/config* ]]; then
        #     exitWithError "CODE ME, please! I beg you."
            # get the highest config file from all and then cat it to ${BUILDDIR}/.config"
        else
            exitWithError "We couldn't find a config file to use."
        fi
    fi
}

modifyConfig() {
    local rootfstype
    local rootuuid
    local txt
    # local swapuuid

    rootfstype="$(lsblk -o MOUNTPOINT,FSTYPE | grep -E "^/ " | awk '{print $2}')"
    rootuuid="$(lsblk -o MOUNTPOINT,PARTUUID | grep -E "^/ " | awk '{print $2}')"
    # swapuuid="/dev/$(lsblk -o FSTYPE,KNAME | grep -E "^swap " | awk '{print $2}')"
    txt="CONFIG_CMDLINE_BOOL=y\\n"
    txt="${txt}CONFIG_CMDLINE=\"rootfstype=${rootfstype} root=PARTUUID=${rootuuid} rw quiet\"\\n"
    # txt="${txt}CONFIG_CMDLINE_OVERRIDE=y\n"

    # sed -Ei "s/^#? ?CONFIG_CMDLINE_OVERRIDE(=[ynm]| is not set)//" "$CONFIGFILE"
    sed -Ei "s/^#? ?CONFIG_CMDLINE[ =].*//" "$CONFIGFILE"
    sed -Ei "s/^#? ?CONFIG_CMDLINE_BOOL(=[ynm]| is not set)/${txt}/" "$CONFIGFILE"

    if [[ -z $TRACKVERSION ]]; then
        sed -Ei "s/^CONFIG_LOCALVERSION=\".*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" "$CONFIGFILE"
    else
        sed -Ei "s/^CONFIG_LOCALVERSION=\".*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}-${TRACKVERSION}\"/" "$CONFIGFILE"
    fi

    # sed -Ei "s/^#? ?CONFIG_PM_STD_PARTITION[ =].*//" "$CONFIGFILE"
}


runOlddefconfig(){
    printLine "make -j $cpuno V=0 O=${BUILDDIR} olddefconfig"
    make -j "$cpuno" V=0 O="$BUILDDIR" olddefconfig 2>> "${BUILDDIR}/Error" 1> /dev/null
    if [[ $? -ne 0 ]]; then
        exitWithError "'make olddefconfig' failed"
    fi
}

editConfig(){
    if [[ $EDITCONFIG -eq 1 ]]; then
        printLine "make -j $cpuno V=0 O=${BUILDDIR} menuconfig"
        make -j "$cpuno" V=0 O="$BUILDDIR" menuconfig 2>> "${BUILDDIR}/Error"
        if [[ $? -ne 0 ]]; then
            exitWithError "'make menuconfig' failed"
        fi
    fi
}

buildKernel(){
    printLine "make -j $cpuno V=0 O=${BUILDDIR} all"
    make -j "$cpuno" V=0 O="$BUILDDIR" all 2>> "${BUILDDIR}/Error" 1> /dev/null
    if [[ $? -ne 0 ]]; then
        exitWithError "'make all' failed"
    fi
}

buildModules(){
    if [[ -d $MODULESDIR ]]; then
        printLine "Removing $MODULESDIR directory"
        rm -rf "$MODULESDIR"
    fi

    printLine "make -j $cpuno V=0 O=${BUILDDIR} modules_install headers_install"
    make -j "$cpuno" V=0 O="${BUILDDIR}" modules_install headers_install 2>> "${BUILDDIR}/Error" 1> /dev/null
    if [[ $? -ne 0 ]]; then
        exitWithError "'make modules_install headers_install' failed"
    fi
}


install(){
    if [[ -f $BUILDDIR/System.map ]]; then
        printLine "Copying $BUILDDIR/System.map -> /boot/System.map"
        cp --remove-destination "$BUILDDIR/System.map" "/boot/System.map"
    else
        exitWithError "File $BUILDDIR/System.map doesn't exists"
    fi

    if [[ -f $BUILDDIR/arch/x86_64/boot/bzImage ]]; then
        printLine "Copying $BUILDDIR/arch/x86_64/boot/bzImage -> /boot/vmlinuz-${FULLKERNELNAME}"
        cp --remove-destination "$BUILDDIR/arch/x86_64/boot/bzImage" "/boot/vmlinuz-${FULLKERNELNAME}"
    else
        exitWithError "File $BUILDDIR/arch/x86_64/boot/bzImage doesn't exists"
    fi

    printLine "Creating initramfs-${FULLKERNELNAME}.img file"
    mkinitcpio -k "${FULLKERNELNAME}" -g "/boot/initramfs-${FULLKERNELNAME}.img"
    if [[ $? -ne 0 ]]; then
        exitWithError "mkinitcpio failed"
    fi

    printLine "Creating entry file"
(cat <<EOF
title Arch Linux
linux /vmlinuz-${FULLKERNELNAME}
version ${FULLKERNELNAME}
initrd /intel-ucode.img
initrd /initramfs-${FULLKERNELNAME}.img
EOF
) > "/boot/loader/entries/${FULLKERNELNAME}.conf"
}


checkSystem
cd "$SOURCESDIR" || exit 2
getVersionSources
setVariables
setbuilddir
moveTemplate
getTemplateVersion
vercomp "$KERNELVERSION" "$TEMPLATEVERSION"
versionValidation=$?
if [[ $versionValidation -eq 1 ]]; then
    runOlddefconfig
elif [[ $versionValidation -eq 2 ]]; then
    exitWithError "You are downgrading your kernel, this is not supported"
fi
modifyConfig
editConfig
buildKernel
buildModules
install

if [[ -x $ONDONE ]]; then
    printLine "Calling ${ONDONE} ${FULLKERNELNAME} ${BUILDDIR}"
    $ONDONE "${FULLKERNELNAME}" "${BUILDDIR}"
    if [[ $? -ne 0 ]]; then
        exitWithError "This command \"${ONDONE} ${FULLKERNELNAME} ${BUILDDIR}\" failed"
    fi
fi

printLine "Kernel ${FULLKERNELNAME} was successfully installed"
printLine "Bye!"
exit 0
