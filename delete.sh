#!/usr/bin/env bash
unalias ls 2>/dev/null
for kernel in $@
do
    echo "Removing ${kernel} files on /boot"
    rm -f /boot/*${kernel}*
    rm -f /boot/loader/entries/${kernel}.conf
    echo "Removing /usr/lib/modules/${kernel} directory"
    rm -rf /usr/lib/modules/${kernel}
    echo "Removing /opt/kernel-sources/${kernel} directory"
    rm -rf /opt/kernel-sources/${kernel}
done
