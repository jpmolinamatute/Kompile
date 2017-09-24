#!/usr/bin/env bash

if [[ -f /proc/cpuinfo ]]; then
    echo "CPU Info" > ./cpu
    echo "--------" >> ./cpu
    cat /proc/cpuinfo | grep -E "(vendor_id|model name)" | sort -u >> ./cpu
    echo -n "Number of Processors: " >> ./cpu
    cat /proc/cpuinfo | grep -c "processor	:" >> ./cpu
    echo " " >> ./cpu
    echo "Kernel driver in use" >> ./cpu
    echo "--------------------" >> ./cpu
    lspci -kv | grep -E "Kernel driver in use:" | cut -d ':' -f 2 | cut -d' ' -f 2 | sort -u >> ./cpu
    echo " " >> ./cpu
    echo "Kernel modules" >> ./cpu
    echo "--------------" >> ./cpu
    lspci -kv | grep -E "Kernel modules:" | cut -d ':' -f 2 | cut -d' ' -f 2 | sort -u >> ./cpu
    cat ./cpu
fi
# lspci -kv | grep -E "(Kernel driver in use:|Kernel modules:)" | cut -d ':' -f 2 | cut -d' ' -f 2 | sort -u
