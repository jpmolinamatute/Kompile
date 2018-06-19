#!/usr/bin/env bash

BASESOURCEDIR="/usr/src"
cpuno=$(grep -Pc "processor\\t:" /proc/cpuinfo)

# vars set by either user or program
KERNELVERSION=

# vars set WITH user input
FULLKERNELNAME=
BUILDDIR=
CONFIGFILE=
TEMPLATEVERSION=
MODULESDIR=
TRACKVERSION=
SOURCESDIR=


# vars set by user input
KERNELNAME=
BASEBUILDDIR=
TEMPLATEFILE=
SOURCEVERSIONLABEL=
EDITCONFIG=0
DOWNLOAD=0
# ONDONE=



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
    echo "$1" >> ${BUILDDIR}/Error
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
    if [[ -n $dir ]]; then
        if [[ ! -d $dir || ! -w $dir ]]; then
            echo -e "\\033[0;31mError: Directory $dir doesn't exists or it's not writable${NC}"
            exit 2
        fi
    else
        echo -e "\\033[0;31mError: Directory $2 doesn't exists or it's not writable${NC}"
        exit 2
    fi
}

checkSystem(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "\\033[0;31mError: This script must be run as root"
        exit 2
    fi
    command -v bc &> /dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "\\033[0;31mError: Please install bc"
        exit 2
    fi

    if [[ -z $KERNELNAME ]]; then
        echo -e "\\033[0;31mError: Please provide a name"
        exit 2
    fi

    checkDirectory $BASESOURCEDIR
    checkDirectory $BASEBUILDDIR "Base Building"

    if [[ $DOWNLOAD -eq 0 ]]; then
        if [[ -n $SOURCEVERSIONLABEL ]]; then
            checkDirectory "${BASESOURCEDIR}/${SOURCEVERSIONLABEL}"
        else
            echo -e "\\033[0;31mError: Please provide a Kernel version Label"
            exit 2
        fi
    elif [[ $DOWNLOAD -eq 1 && -n $SOURCEVERSIONLABEL ]]; then
        echo -e "\\033[0;31mError: Source label and download cannot be used together"
        exit 2
    fi

}

getVersionSources() {
    cd "$SOURCESDIR" || exit 2
    KERNELVERSION="$(make -s kernelversion 2> /dev/null)"
}

setVariables() {
    if [[ $DOWNLOAD -eq 0 ]]; then
        SOURCESDIR="${BASESOURCEDIR}/${SOURCEVERSIONLABEL}"
        getVersionSources
    fi

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
    printLine "make -j $cpuno V=0 O=$BUILDDIR distclean"
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

save(){
    if [[ -d $SAVECONFIG ]]; then
        printLine "Saving ${BUILDDIR}/.config to $SAVECONFIG/config-${FULLKERNELNAME}"
        cp --remove-destination "${BUILDDIR}/.config" "$SAVECONFIG/config-${FULLKERNELNAME}"
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

usage() {
    cat >&2 <<EOF
    Usage: $THISSCRIPT [options]

    Options:
      --help                      : This output.
      --edit                      : Either or not to run GUI tool to modify config file.
      --download                  : Either or not to download the kernel sources.
      --build PATH                : Building directory. This directory is where hearder will be saved
                                    and the kernel will be built.
      --source PATH               : Source directory. This directory is where the kernel sources are
                                    saved.
      --name NAME                 : How you want to name this kernel.
      --file PATH                 : Path to a config file.
      --save                      : Path to save config file
      --ondone                    : Path to script to execute after $THISSCRIPT
EOF
}

getUserInput() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        "--help")
            usage
            exit 0
            ;;
        "--edit")
            shift
            EDITCONFIG=1
            ;;
        "--download")
            shift
            DOWNLOAD=1
            ;;
        "--build")
            shift
            BASEBUILDDIR="$(readlink -f "$1")"
            shift
            ;;
        "--ondone")
            shift
            ONDONE="$(readlink -f "$1")"
            shift
            ;;
        "--save")
            shift
            SAVECONFIG="$1"
            shift
            ;;
        "--source")
            shift
            SOURCEVERSIONLABEL="$1"
            shift
            ;;
        "--name")
            shift
            KERNELNAME="$1"
            shift
            ;;
        "--file")
            shift
            TEMPLATEFILE="$(readlink -f "$1")"
            shift
            ;;
        *)
            exitWithError "Unknown command-line option $1"
            ;;
        esac
    done
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

downloadSources() {
    local html
    local tarFile
    local mayorVersion
    local tarPath
    local prefix="linux-"
    local suffic="\\.tar\\.xz"
    html="$(wget --output-document - --quiet https://www.kernel.org/ | grep -A 1 "latest_link")"
    tarFile="$(echo "$html" | grep -Eo "linux-[4-9]\\.[0-9]+\\.?[0-9]*\\.tar\\.xz")"
    mayorVersion="$(echo "$tarFile" | cut -d'-' -f2 | cut -d'.' -f1)"
    KERNELVERSION="${tarFile#$prefix}"
    KERNELVERSION="${KERNELVERSION%$suffic}"
    SOURCESDIR="${BASESOURCEDIR}/linux-${KERNELVERSION}"
    tarPath="${BASESOURCEDIR}/${tarFile}"

    if [[ ! -f $tarPath ]]; then
        printLine "Downloading latest Linux Kernel: version found ${KERNELVERSION}"
        wget -P "$BASESOURCEDIR" --https-only "https://cdn.kernel.org/pub/linux/kernel/v${mayorVersion}.x/${tarFile}"
        if [[ $? -ne 0 ]]; then
            exitWithError "Downloading ${tarFile} failed"
        fi
    else
        if [[ -d $SOURCESDIR ]]; then
            printLine "Removing sources downloaded previously"
            rm -rf "$SOURCESDIR"
        fi
    fi

    printLine "Untaring $tarPath"
    tar -xf "$tarPath" -C "$BASESOURCEDIR" --overwrite
    if [[ $? -ne 0 ]]; then
        exitWithError "Untaring $tarPath failed"
    fi
}


getUserInput "$@"
checkSystem

if [[ $DOWNLOAD -eq 1 ]]; then
    downloadSources
    setVariables
    cd "$SOURCESDIR" || exit 2
else
    setVariables
fi

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
save

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
