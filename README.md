CloudStackImageScripts
======================

Scripts to create Xen templates for CloudStack.


createUbuntuCSimageXen.sh: This script will download the root tar from the Ubuntu cloud image repository and create a version of it that works with XenServer Cloudstack intallations.  Prior to importing it as a template one will have to convert it into a vhd file which the createVHD script will do.  
In addition to Xenifying the Ubuntu image, it will do the following:
1) Patch the default 12.04 cloud-init so that it works with CloudStack (requires the file DataSourceCloudStack.patch)
2) Configures default cloud-init config to enable ssh access via password and sets the ubuntu user password
3) Install xen guest utilities.  Requires xe-guest-utilities_6.0.2-766_amd64.deb to be in the same path.  It may be obtained from the XenServer tools install iso which comes with XenCenter.
4) Installs CloudStack set password script
Please note this script should be run on an ubuntu 12.04 machine for best results.  The directory it is run from should have at least 10+G available.
Once done, a file by the name of ubuntu-12.04.3-server-cloudimg-amd64.fs will be in the same path as this script.  Please copy this file to a XenServer host with an NFS SR in order to run the createVDH.sh script.

createVDH.sh: This script will create a template file that can be imported into Cloudstack for use with XenServer hosts.  It requires the host to have an NFS SR.  It is ok to run this on a host that is part of a CloudStack deployment.  It will create a VDI, import the file passed into it, compress the .vhd from the VDI into a .vhd.bz2 and then destroy the VDI.
