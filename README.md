These two scripts help me to compile my own Linux kernel. Currently only works with Arch Linux with UEFI **(for now)**  

The main idea of this script is to help user to test their own kernel configuration based on a previous config file. This way user can do little modification between each test and at the same time to have a way to recover from a mistake.
This script is going to attempt to load the config file from the current kernel. It also provide an option to load a specific config file.

This is a **temporary** procedure to compile your own kernel using these scripts.

1.  Download the linux kernel source from [https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.12.9.tar.xz](https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.12.9.tar.xz "Linux Kernel") .
2.  Untar the linux kernel under /usr/scr.
3.  Change directory to /usr/scr/linux-4.12.9.
4.  Copy ./user and ./root to /usr/scr/linux-4.12.9.
5.  Run ./user as regular user.
    ```shell
    ./user.sh --name SOMENAME --edit --path SOMEPATH
    ```

Where SOMENAME is any name that you want to call this new kernel and SOMEPATH is a path where to have the linux headers, this directory must be writtable by the regular user that is running the script. You also have the `--file` option to pass a linux config file other than from the current kernel.  
6. At some point this script is going to ask you for your password to run the rest of the script as root.  
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
