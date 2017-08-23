#!/usr/bin/env bash

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
    *)
        Usage
        echo "" >&2
        Fail "Unknown command-line option $1"
        ;;
    esac
done

KERNELDIR="${KERNELDIR}/${VERSION}-${KERNELNAME}"

if [[ -z $KERNELNAME ]]; then
    >&2 echo "ERROR: a name for the kernel is needed"
    exit 2
fi

if [[ ! -f ./root.sh ]]; then
    >&2 echo "Error: ./root.sh file doesn't exists"
fi


if [[ -d $KERNELDIR ]]; then
    echo "=>    make O=$KERNELDIR distclean"
    make O=$KERNELDIR distclean
else
    echo "=>    mkdir ${KERNELDIR}"
    mkdir ${KERNELDIR}
fi

zcat --version > /dev/null

if [[ $? -eq 0 &&  -f /proc/config.gz ]]; then
    echo "=>    zcat /proc/config.gz > ${KERNELDIR}/.config"
    zcat /proc/config.gz > ${KERNELDIR}/.config
elif [[ -f /boot/config* ]]; then
    >&2 echo "CODE ME, please! I beg you."
    # get the highest config file from all and then cat it to ${KERNELDIR}/.config"
    exit 2
else
    >&2 echo "We couldn't find a config file to use."
    configFound=0
fi


if [[ $configFound -eq 1 ]]; then
    sed -Ei "s/^CONFIG_LOCALVERSION=\"[a-z-]*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" ${KERNELDIR}/.config
    shouldRunOldConfig
    versionValidation=$?
    if [[ $versionValidation -eq 1 ]]; then
        whatToRun="olddefconfig"
    elif [[ $versionValidation -eq 2 ]]; then
        >&2 echo "ERROR: you are downgrading your kernel, this is not supported"
        exit 2
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
    sed -Ei "s/^CONFIG_LOCALVERSION=\"[a-z-]*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" ${KERNELDIR}/.config
fi

whatToRun="${whatToRun} all"
echo "=>    running ${whatToRun}"
make -j $cpuno V=0 O=${KERNELDIR} $whatToRun 1> /dev/null 2> ${KERNELDIR}/Error

if [[ $? -eq 0 ]]; then
    echo "Please press a key to continue"
    read
    sudo ./root.sh ${KERNELNAME}
    exit $?
else
    >&2 echo "ERROR: make failed"
    exit 2
fi
