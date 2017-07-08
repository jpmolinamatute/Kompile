#!/usr/bin/env bash
KERNELNAME=$1
KERNELNAME=${KERNELNAME:-"unknown"}
VERSION="$(make -s kernelversion)"
KERNELDIR="/opt/kernel-sources/${VERSION}-${KERNELNAME}"
configFound=1
export CHOST="x86_64-pc-linux-gnu"
export CFLAGS="-march=native -O2 -pipe -msse3"
export CXXFLAGS="${CFLAGS}"

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

if [[ -d $KERNELDIR ]]; then
    echo "=>    make O=$KERNELDIR distclean"
    make O=$KERNELDIR distclean
else
    echo "=>    mkdir ${KERNELDIR}"
    mkdir ${KERNELDIR}
fi

zcat --version > /dev/null

if [[ $? -eq 0 &&  -f /proc/config.gz ]]; then
    echo "=>   zcat /proc/config.gz > ${KERNELDIR}/.config"
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
        echo "=> running olddefconfig xconfig all"
        make O=${KERNELDIR} olddefconfig xconfig all
        makeStatus=$?
    elif [[ $versionValidation -eq 0 ]]; then
        echo "=> running xconfig all"
        make O=${KERNELDIR} xconfig all
        makeStatus=$?
    elif [[ $versionValidation -eq 2 ]]; then
        >&2 echo "ERROR: you are downgrading your kernel, this is not supported"
        exit 2
    fi
else
    make O=${KERNELDIR} xconfig
    sed -Ei "s/^CONFIG_LOCALVERSION=\"[a-z-]*\"$/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/" ${KERNELDIR}/.config
    make O=${KERNELDIR} all
    makeStatus=$?
fi

if [[ $makeStatus -eq 0 ]]; then
    echo "Please run root.sh"
else
    >&2 echo "ERROR: make failed"
fi

exit $makeStatus
