#!/bin/bash
if [ -z $1 ]
then
   echo "Usage: $0 <disk file>"
   echo -e "\n!!! This should be run from a XenServer host with an NFS SR !!!\n"
   exit 
fi

grep XenServer /etc/redhat-release
if [ $? -ne 0 ] ; then
   echo -e "\n!!! This should be run from a XenServer host with an NFS SR !!!\n"
   exit
fi

FILE=$1
IMG=${FILE%.*}
echo "Base filename: $IMG"

# get an NFS UUID
TSR=`xe sr-list type=nfs --minimal`
SR=$TSR
echo "SR List: $TSR"
if [ -z $TSR ] ; then
   echo "You need an NFS SR for this to work."
   exit
fi
if [[ "$TSR" == *,* ]] ; then
   SR=${TSR%%,*}
   echo "More than one nfs SR.  Picking 1st one: $SR"
fi

echo "Using SR: $SR"

VDI=`xe vdi-create virtual-size=10GiB sr-uuid=$SR type=user name-label="$IMG"`
if [ $? -ne 0 ] ; then 
   echo "!!!! Failed to create vdi: xe vdi-create virtual-size=10GiB sr-uuid=$SR type=user name-label=\"$IMG\""
   exit
fi
echo "Created VDI with uuid: $VDI"
echo "Importing $FILE into VDI. This will take a few minutes"
xe vdi-import filename=$FILE uuid=$VDI
if [ $? -ne 0 ] ; then 
   echo "!!!! Failed to import image: xe vdi-import filename=$FILE uuid=$VDI"
   exit
fi
echo "Done with import"
echo "Compressing file.  This will also take a few minutes"
bzip2 -c $VDI.vhd > $IMG.vhd.bz2
xe vdi-destroy uuid=$VDI
echo "Done! Copy/Move $IMG.vhd.bz2 to a place where you can download it to CloudStack"


