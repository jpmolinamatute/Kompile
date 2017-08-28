#!/usr/bin/env bash

# TODO: merge user.sh and root.file
# FIXME: run 'make xconfig' as root but in a regular user session. Right now when running this command as root get Display not found error
# TODO: download kernel sources from internet
# TODO: untar linux kernel
# TODO: validate config file loaded by the user
# TODO: implement verbose option
# TODO: implement lspci -k, lsmod and other command in helpful fashion so that the user knows what modules must keep
VERSION="$(make -s kernelversion)"
KERNELDIR="/opt/kernel-sources"
configFound=1
export CHOST="x86_64-pc-linux-gnu"
export CFLAGS="-march=native -O2 -pipe -msse3"
export CXXFLAGS="${CFLAGS}"
RUNXCONFIG="false"
cpuno=$(grep -Pc "processor\t:" /proc/cpuinfo)
cpuno=$(($cpuno + 1))

# FROM https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash
# thanks Dennis Williamson
vercomp () {
    if [[ $1 == $2 ]]
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

shouldRunOldConfig () {
    oldVersion="$(grep -E "# Linux/x86 [45]\.[0-9]{1,2}\.[0-9]{1,2} Kernel Configuration" ${KERNELDIR}/.config | grep -Eo "[45]\.[0-9]{1,2}\.[0-9]{1,2}")"
    vercomp $VERSION $oldVersion
    return $?
}

exitWithError () {
    local COLOR='\033[0;31m'
    local NC='\033[0m'
    echo -e "${COLOR}$1${NC}"
    exit 2
}

printLine (){
    local COLOR='\033[1;32m'
    local NC='\033[0m'
    echo -e "${COLOR}==>    $1${NC}"
}

refineKernelName (){
    local kernelPath="/boot/vmlinuz-${VERSION}-${KERNELNAME}"
    if [[ -f $kernelPath ]]; then
        printLine "A Kernel ${VERSION}-${KERNELNAME} was found!. Do you want to Replace it or Increment it (r, i)"
        read answer

        if [[ $answer == "i" || $answer == "I" ]]; then
            local FILES="${kernelPath}*"
            for f in $FILES
            do
                trackversion=$(cut -d'-' -f4 <<<$f)
            done

            if [[ -z $trackversion ]]; then
                local trackversion=1
            else
                local trackversion=$(($trackversion + 1))
            fi

            KERNELNAME="${KERNELNAME}-${trackversion}"
        fi
    fi
}

if [[ ! -f "./root.sh" ]]; then
    exitWithError "Error: ./root.sh file doesn't exists"
fi

while [ $# -gt 0 ]; do
    case "$1" in
    "--help")
        Usage
        exit 0
        ;;
    "--verbose")
        shift
        # LoggedOut "Turned on verbose output."
        VERBOSE=1
        ;;
    "--edit")
        shift
        # LoggedOut "Turned on verbose output."
        RUNXCONFIG="true"
        ;;
    "--path")
        shift
        KERNELDIR="$1"
        shift
        ;;
    "--name")
        shift
        KERNELNAME="$1"
        shift
        ;;
    "--file")
        shift
        CONFIGFILE="$1"
        shift
        ;;
    *)
        exitWithError "Unknown command-line option $1"
        ;;
    esac
done

if [[ -n $KERNELNAME ]]; then
    refineKernelName
else
    exitWithError "ERROR: a name for the kernel is needed"
fi

KERNELDIR="${KERNELDIR}/${VERSION}-${KERNELNAME}"

if [[ -d $KERNELDIR ]]; then
    printLine "make O=$KERNELDIR distclean"
    make O=$KERNELDIR distclean 1> /dev/null 2>> ${KERNELDIR}/Error
else
    printLine "mkdir ${KERNELDIR}"
    mkdir ${KERNELDIR}
fi


if [[ -f $CONFIGFILE ]]; then
    printLine "Config file found: ${CONFIGFILE}"
    cp $CONFIGFILE ${KERNELDIR}/.config
else
    zcat --version > /dev/null 2>&1
    if [[ $? -eq 0 &&  -f /proc/config.gz ]]; then
        printLine "zcat /proc/config.gz > ${KERNELDIR}/.config"
        zcat /proc/config.gz > ${KERNELDIR}/.config
    elif [[ -f /boot/config* ]]; then
        exitWithError "CODE ME, please! I beg you."
        # get the highest config file from all and then cat it to ${KERNELDIR}/.config"
    else
        exitWithError "We couldn't find a config file to use."
        configFound=0
    fi
fi

if [[ $configFound -eq 1 ]]; then
    sed -Ei "s/^CONFIG_LOCALVERSION=\"[a-z0-9-]*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" ${KERNELDIR}/.config
    shouldRunOldConfig
    versionValidation=$?
    if [[ $versionValidation -eq 1 ]]; then
        whatToRun="olddefconfig"
    elif [[ $versionValidation -eq 2 ]]; then
        exitWithError "ERROR: you are downgrading your kernel, this is not supported"
    fi
    if [[ $RUNXCONFIG == "true" ]]; then
        whatToRun="${whatToRun} xconfig"
    fi
else
    if [[ $RUNXCONFIG == "true" ]]; then
        whatToRun="xconfig"
    else
        whatToRun=""
        make O=${KERNELDIR} defconfig
    fi
    make O=${KERNELDIR} xconfig
    sed -Ei "s/^CONFIG_LOCALVERSION=\"[a-z0-9-]*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" ${KERNELDIR}/.config
fi

whatToRun="${whatToRun} all"
printLine "running ${whatToRun}"
make -j $cpuno V=0 O=${KERNELDIR} $whatToRun 1> /dev/null 2> ${KERNELDIR}/Error

if [[ $? -eq 0 ]]; then
    printLine "Please press a key to continue"
    read
    sudo ./root.sh ${KERNELNAME} ${KERNELDIR}
    exit $?
else
    exitWithError "ERROR: make failed"
fi
