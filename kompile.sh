#!/usr/bin/env bash
THISSCRIPT="$(basename "$0")"
SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORFILE="${SRCDIR}/Error"
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
DRY=0
SAVECONFIG=
ONDONE=

vercomp() {
    # FROM https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash
    # thanks Dennis Williamson
    if [[ $1 == "$2" ]]; then
        return 0
    fi
    local IFS='.'
    local i ver1 ver2
    read -r -a ver1 <<<"$1"
    read -r -a ver2 <<<"$2"

    # fill empty fields in ver1 with zeros
    for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i = 0; i < ${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

writeToErrorFile() {
    if [[ -n $1 ]]; then
        echo "$1" >>"$ERRORFILE"
    fi
}

writeErrorSectionFile() {
    if [[ $1 == "start" ]]; then
        local startend="START"
    else
        local startend="END"
    fi
    writeToErrorFile "****** $startend OF SECTION: $2 ******"
}

exitWithError() {
    local red='\033[0;31m'
    local end='\033[0m'
    echo -e "${red}ERROR: $1${end}" >&2
    writeToErrorFile "ERROR: $1"
    if [[ -n $2 ]]; then
        writeErrorSectionFile "end" "$2"
    fi
    echo "Please read $ERRORFILE for more information"
    exit 2
}

printLine() {
    local green='\033[1;32m'
    local end='\033[0m'
    echo -e "${green}==>    $1${end}"
}

checkDirectory() {
    local dir=$1
    if [[ -n $dir ]]; then
        if [[ ! -d $dir || ! -w $dir ]]; then
            exitWithError "Directory $dir doesn't exists or it's not writable"
        fi
    else
        exitWithError "Directory $2 doesn't exists or it's not writable"
    fi
}

checkSystem() {
    if [[ $DRY -eq 1 ]]; then
        local tmpkernel="${SRCDIR}/tmpKernel"
        if [[ ! -d $tmpkernel ]]; then
            if ! mkdir "$tmpkernel" 2>/dev/null; then
                echo "ERROR: ${SRCDIR} is not writable"
                exit 2
            fi
        fi
        DOWNLOAD=1
        BASESOURCEDIR=$tmpkernel
        BASEBUILDDIR=$tmpkernel
        SAVECONFIG=$SRCDIR
        ERRORFILE="${tmpkernel}/Error"
    fi
    echo "#####  Error log start here  #####" >"$ERRORFILE"
    local sectionName="checking system"
    writeErrorSectionFile "start" "$sectionName"
    if [[ $DRY -eq 0 && $EUID -ne 0 ]]; then
        exitWithError "This script must be run as root" "$sectionName"
    fi

    if ! command -v bc &>/dev/null; then
        exitWithError "Please install bc" "$sectionName"
    fi

    if ! command -v zcat &>/dev/null; then
        exitWithError "Please install zcat" "$sectionName"
    fi

    if [[ -z $KERNELNAME ]]; then
        exitWithError "Please provide a name" "$sectionName"
    fi

    checkDirectory "$BASESOURCEDIR"
    checkDirectory "$BASEBUILDDIR" "Base Building"

    if [[ $DOWNLOAD -eq 0 ]]; then
        if [[ -n $SOURCEVERSIONLABEL ]]; then
            checkDirectory "${BASESOURCEDIR}/${SOURCEVERSIONLABEL}"
        else
            exitWithError "Please provide a kernel version label" "$sectionName"
        fi
    elif [[ $DOWNLOAD -eq 1 && -n $SOURCEVERSIONLABEL ]]; then
        exitWithError "Source label and download cannot be used together" "$sectionName"
    fi
    writeErrorSectionFile "end" "$sectionName"
}

getVersionSources() {
    cd "$SOURCESDIR" || exit 2
    KERNELVERSION="$(make -s kernelversion 2>/dev/null)"
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
    if [[ -d $BUILDDIR && $DRY -eq 0 ]]; then
        printLine "A Kernel ${KERNELNAME} was found!. Do you want to Replace it or Increment it (r, i)"
        read -r answer

        if [[ $answer =~ [iI] ]]; then
            local FILES="${BUILDDIR}*"
            for f in $FILES; do
                TRACKVERSION=$(basename "$f" | cut -d'-' -f3)
            done

            if [[ -z $TRACKVERSION ]]; then
                TRACKVERSION=1
            else
                TRACKVERSION=$((TRACKVERSION + 1))
            fi

            setVariables
            printLine "mkdir ${BUILDDIR}"
            mkdir "$BUILDDIR"
        fi
    elif [[ ! -d $BUILDDIR ]]; then
        printLine "mkdir ${BUILDDIR}"
        mkdir "$BUILDDIR"
    fi

    printLine "make -j${cpuno} V=0 O=$BUILDDIR distclean"
    if ! make -j"${cpuno}" V=0 O="$BUILDDIR" distclean 2>>"$ERRORFILE" 1>/dev/null; then
        exitWithError "pre cleaning process failed"
    fi
}

moveTemplate() {
    local sectionName="getting config file"
    writeErrorSectionFile "start" "$sectionName"
    if [[ -f $TEMPLATEFILE ]]; then
        printLine "Config file found: $TEMPLATEFILE and copied to $CONFIGFILE"
        if ! cp "$TEMPLATEFILE" "$CONFIGFILE"; then
            exitWithError "copying $TEMPLATEFILE to $CONFIGFILE failed" "$sectionName"
        fi
        if ! chmod 644 "$CONFIGFILE"; then
            exitWithError "changing permission of $CONFIGFILE failed" "$sectionName"
        fi
    else
        local procConfig="/proc/config.gz"
        if [[ -f $procConfig ]]; then
            printLine "Config file found: $procConfig and copied to $CONFIGFILE"
            if ! zcat $procConfig >"$CONFIGFILE"; then
                exitWithError "creating $CONFIGFILE failed" "$sectionName"
            fi
            # elif [[ -f /boot/[Cc]onfig* ]]; then
            #     printLine "Config file found: $procConfig"
            # 	cp "$TEMPLATEFILE" "$CONFIGFILE"
            #     chmod 644 "$CONFIGFILE"
            #     exitWithError "CODE ME, please! I beg you."
            # get the highest config file from all and then cat it to ${BUILDDIR}/.config"
        else
            exitWithError "We couldn't find a config file to use." "$sectionName"
        fi
    fi
    writeErrorSectionFile "end" "$sectionName"
}

modifyConfig() {
    local rootfstype
    local rootuuid
    local txt
    local swapuuid

    rootfstype="$(lsblk -o MOUNTPOINT,FSTYPE | grep -E "^/ " | awk '{print $2}')"
    rootuuid="$(lsblk -o MOUNTPOINT,PARTUUID | grep -E "^/ " | awk '{print $2}')"
    swapuuid="$(lsblk -o FSTYPE,PARTUUID | grep -E "^swap " | awk '{print $2}')"
    txt="CONFIG_CMDLINE_BOOL=y\\n"
    txt="${txt}CONFIG_CMDLINE=\"rootfstype=${rootfstype} root=PARTUUID=${rootuuid} rw\"\\n"
    # txt="${txt}CONFIG_CMDLINE_OVERRIDE=y\n"

    # sed -Ei "s/^#? ?CONFIG_CMDLINE_OVERRIDE(=[ynm]| is not set)//" "$CONFIGFILE"
    sed -Ei "s/^#? ?CONFIG_CMDLINE[ =].*//" "$CONFIGFILE"
    sed -Ei "s/^#? ?CONFIG_CMDLINE_BOOL(=[ynm]| is not set)/${txt}/" "$CONFIGFILE"

    if [[ -z $TRACKVERSION ]]; then
        sed -Ei "s/^CONFIG_LOCALVERSION=\".*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" "$CONFIGFILE"
    else
        sed -Ei "s/^CONFIG_LOCALVERSION=\".*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}-${TRACKVERSION}\"/" "$CONFIGFILE"
    fi

    sed -Ei "s/^#? ?CONFIG_PM_STD_PARTITION[ =].*$/CONFIG_PM_STD_PARTITION=\"PARTUUID=${swapuuid}\"/" "$CONFIGFILE"
    sed -Ei "s/^#? ?CONFIG_DEFAULT_HOSTNAME[ =].*$/CONFIG_DEFAULT_HOSTNAME=\"${KERNELNAME}\"/" "$CONFIGFILE"
}

runOlddefconfig() {
    local validation=$1
    local sectionName="Validating config version"
    writeErrorSectionFile "start" "$sectionName"
    if [[ $validation -eq 1 ]]; then
        printLine "make -j${cpuno} V=0 O=${BUILDDIR} olddefconfig"
        if ! make -j"${cpuno}" V=0 O="$BUILDDIR" olddefconfig 2>>"$ERRORFILE"; then
            exitWithError "'make olddefconfig' failed" "$sectionName"
        fi
    elif [[ $validation -eq 2 ]]; then
        exitWithError "You are downgrading your kernel, this is not supported" "$sectionName"
    fi
    writeErrorSectionFile "end" "$sectionName"
}

saveConfig() {
    if [[ -d $SAVECONFIG ]]; then
        printLine "Copying ${CONFIGFILE} to $SAVECONFIG/config-${FULLKERNELNAME}"
        if ! cp --remove-destination "${CONFIGFILE}" "$SAVECONFIG/config-${FULLKERNELNAME}"; then
            exitWithError "saving ${SAVECONFIG}/config-${FULLKERNELNAME} failed"
        fi
    fi
}

editConfig() {
    local sectionName="editing config file"
    writeErrorSectionFile "start" "$sectionName"
    if [[ $DRY -eq 0 ]]; then
        if [[ $EDITCONFIG -eq 1 ]]; then
            printLine "make -j${cpuno} V=0 O=${BUILDDIR} menuconfig"

            if ! make -j"${cpuno}" V=0 O="$BUILDDIR" menuconfig 2>>"$ERRORFILE"; then
                exitWithError "'make menuconfig' failed" "$sectionName"
            fi
        fi
    else
        printLine "make -j${cpuno} V=0 O=${BUILDDIR} xconfig"
        if ! make -j"${cpuno}" V=0 O="$BUILDDIR" xconfig 2>>"$ERRORFILE"; then
            exitWithError "'make xconfig' failed" "$sectionName"
        fi
    fi
    writeErrorSectionFile "end" "$sectionName"
}

buildKernel() {
    if [[ $DRY -eq 0 ]]; then
        local sectionName="compiling kernel"
        writeErrorSectionFile "start" "$sectionName"
        printLine "make -j${cpuno} V=0 O=${BUILDDIR} all"
        if ! make -j"${cpuno}" V=0 O="$BUILDDIR" all 2>>"$ERRORFILE" 1>/dev/null; then
            exitWithError "'make all' failed" "$sectionName"
        fi
        writeErrorSectionFile "end" "$sectionName"
    fi
}

buildModules() {
    if [[ $DRY -eq 0 ]]; then
        local sectionName="creating kernel modules"
        writeErrorSectionFile "start" "$sectionName"
        if [[ -d $MODULESDIR ]]; then
            printLine "Removing $MODULESDIR directory"
            rm -rf "$MODULESDIR"
        fi

        printLine "make -j${cpuno} V=0 O=${BUILDDIR} modules_install headers_install"

        if ! make -j"${cpuno}" V=0 O="${BUILDDIR}" modules_install headers_install 2>>"$ERRORFILE" 1>/dev/null; then
            exitWithError "'make modules_install headers_install' failed" "$sectionName"
        fi
        writeErrorSectionFile "end" "$sectionName"
    fi
}

usage() {
    cat <<-EOF
Usage: $THISSCRIPT [options]

Options:
--help                      : This output.
--edit                      : Either or not to run GUI tool to modify config file.
--download                  : Either or not to download the kernel sources.
--build PATH                : Building directory. This directory is where hearder will be saved and the kernel will be built.
--source LABEL              : @FIXME
--name NAME                 : How you want to name this kernel.
--file PATH                 : Path to a config file.
--save                      : Path where config file will be saved
--ondone                    : Path to script to execute after $THISSCRIPT
--dry                       : will create a config file in current directory if --save is not specify
EOF
}

runExternalScript() {
    if [[ $DRY -eq 0 && -x $ONDONE ]]; then
        local sectionName="running external script"
        writeErrorSectionFile "start" "$sectionName"
        printLine "Calling ${ONDONE} ${FULLKERNELNAME} ${BUILDDIR}"
        if ! $ONDONE "${FULLKERNELNAME}" "${BUILDDIR}"; then
            exitWithError "This command \"${ONDONE} ${FULLKERNELNAME} ${BUILDDIR}\" failed" "$sectionName"
        fi
        writeErrorSectionFile "end" "$sectionName"
    fi
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
        "--dry")
            shift
            DRY=1
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

install() {
    if [[ $DRY -eq 0 ]]; then
        local sectionName="installing new kernel files"
        writeErrorSectionFile "start" "$sectionName"
        if [[ -f $BUILDDIR/System.map ]]; then
            printLine "Copying $BUILDDIR/System.map -> /boot/System.map"
            cp --remove-destination "$BUILDDIR/System.map" "/boot/System.map"
        else
            exitWithError "File $BUILDDIR/System.map doesn't exists" "$sectionName"
        fi

        if [[ -f $BUILDDIR/arch/x86_64/boot/bzImage ]]; then
            printLine "Copying $BUILDDIR/arch/x86_64/boot/bzImage -> /boot/vmlinuz-${FULLKERNELNAME}"
            cp --remove-destination "$BUILDDIR/arch/x86_64/boot/bzImage" "/boot/vmlinuz-${FULLKERNELNAME}"
        else
            exitWithError "File $BUILDDIR/arch/x86_64/boot/bzImage doesn't exists" "$sectionName"
        fi

        printLine "Creating initramfs-${FULLKERNELNAME}.img file"

        if ! mkinitcpio -k "${FULLKERNELNAME}" -g "/boot/initramfs-${FULLKERNELNAME}.img"; then
            exitWithError "mkinitcpio failed" "$sectionName"
        fi

        printLine "Saving $CONFIGFILE to /boot/config-${FULLKERNELNAME}"
        cp --remove-destination "${CONFIGFILE}" "/boot/config-${FULLKERNELNAME}"

        printLine "Creating entry file"
        cat <<-EOF >"/boot/loader/entries/${FULLKERNELNAME}.conf"
title Arch Linux
linux /vmlinuz-${FULLKERNELNAME}
version ${FULLKERNELNAME}
initrd /intel-ucode.img
initrd /initramfs-${FULLKERNELNAME}.img
EOF
        writeErrorSectionFile "end" "$sectionName"
        printLine "Kernel ${FULLKERNELNAME} was successfully installed"
    fi
}

downloadSources() {
    if [[ $DOWNLOAD -eq 1 ]]; then
        local tarFile
        local mayorVersion
        local tarPath
        local prefix="linux-"
        local suffic="\\.tar\\.xz"
        local sectionName="downloading sources"
        writeErrorSectionFile "start" "$sectionName"
        tarFile="$(wget --output-document - --quiet https://www.kernel.org/ | grep -A 1 "latest_link" | grep -Eo "linux-[4-9]\\.[0-9]+\\.?[0-9]*\\.tar\\.xz")"
        mayorVersion="$(echo "$tarFile" | cut -d'-' -f2 | cut -d'.' -f1)"
        KERNELVERSION="${tarFile#$prefix}"
        KERNELVERSION="${KERNELVERSION%$suffic}"
        SOURCESDIR="${BASESOURCEDIR}/linux-${KERNELVERSION}"
        tarPath="${BASESOURCEDIR}/${tarFile}"

        if [[ ! -f $tarPath ]]; then
            printLine "Downloading latest Linux Kernel: version found ${KERNELVERSION}"

            if ! wget -P "$BASESOURCEDIR" --https-only "https://cdn.kernel.org/pub/linux/kernel/v${mayorVersion}.x/${tarFile}"; then
                exitWithError "Downloading ${tarFile} failed" "$sectionName"
            fi
        else
            if [[ -d $SOURCESDIR ]]; then
                printLine "Removing sources downloaded previously"
                rm -rf "$SOURCESDIR"
            fi
        fi

        printLine "Untaring $tarPath"

        if ! tar -xf "$tarPath" -C "$BASESOURCEDIR" --overwrite; then
            exitWithError "Untaring $tarPath failed" "$sectionName"
        fi
        writeErrorSectionFile "end" "$sectionName"
        setVariables
        cd "$SOURCESDIR" || exit 2
    else
        setVariables
    fi

}

getUserInput "$@"
checkSystem
downloadSources
setbuilddir
moveTemplate
getTemplateVersion
vercomp "$KERNELVERSION" "$TEMPLATEVERSION"
versionValidation=$?
runOlddefconfig $versionValidation
modifyConfig
editConfig
buildKernel
buildModules
install
saveConfig
runExternalScript

printLine "Bye!"
exit 0
