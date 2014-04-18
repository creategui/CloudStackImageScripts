CloudStackImageScripts
======================

Scripts to create Xen templates for CloudStack.

<<<<<<< HEAD
Please note that the ubuntu script has gone through a significant makeover in order to directly create a vhd.

createUbuntuCSimageXen.sh
-------------------------
This script will download the root tar from the Ubuntu precise cloud image repository (http://cloud-images.ubuntu.com/releases/precise/release/) and create a vhd that works with XenServer Cloudstack intallations.  

In addition to "Xenifying" the Ubuntu image, it will do the following:
1. Patch the default 12.04 cloud-init so that it works with CloudStack (requires the file DataSourceCloudStack.patch from this repo)
1. Configures default cloud-init config to enable ssh access via password and sets the ubuntu user password
1. Install xen guest utilities.  Requires xe-guest-utilities_6.0.2-766_amd64.deb to be in the same path.  It may be obtained from the XenServer tools install iso which comes with XenCenter.
1. Installs CloudStack set password script.  It gets this file from: https://github.com/shankerbalan/cloudstack-scripts/raw/master/cloud-set-guest-password-ubuntu

Please note this script should be run on an ubuntu 12.04 machine for best results.  The directory it is run from should have at least 10+G available.

Once done, a file by the name of ubuntu-12.04-server-cloudimg-amd64.vhd will be in the same path as this script.  You should be able to register this file as a template in CloudStack.

Other scripts
=============

mountVHD.sh
-----------
Takes a vhd file and a mount point and mounts it.

unmountVDH.sh
-------------
Unmounts a vhd file.  It searches for the vhd in "tap-ctl list" and unmounts it as well as cleaning up the tap device.

>>>>>>> 696b1e637bacfc977416fb47bfc64500ba50259d
