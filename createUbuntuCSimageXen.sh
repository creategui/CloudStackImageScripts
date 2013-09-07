#!/bin/bash

### Create Ubuntu 12.04.3 raw disk file for Xen from cloud-images.ubuntu.com images
# http://cloud-images.ubuntu.com/releases/precise/release/

## Make sure to use root tar file
LINK=http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04.3-server-cloudimg-amd64-root.tar.gz
FILE=${LINK##*/}
IMG=${FILE%-*}

#Download file if not already
if [ ! -e "$FILE" ] ; then
   echo "Downloading Cloud Image Root tar"
   wget $LINK
   if [ $? -ne 0 ] ; then 
      echo "!!!!!!!! Download failed ($LINK)."
      exit
   fi
else
   echo "Using existing Cloud Image Root tar"
   ls -l $FILE
fi

#create disk file
if [ -e "$IMG.fs" ] ; then
   echo "Disk File $IMG.fs exists. Please move/delete it and re-run"
   exit
else
   echo "Create $IMG.fs disk file"
   dd if=/dev/zero of=$IMG.fs bs=1M count=10240
   #mkfs.ext4 -F $IMG.fs
   mke2fs -F -j $IMG.fs
fi

#mount disk file
if [ -e "$IMG" ] ; then
   mount | grep $IMG
   if [ $? -eq 0 ] ; then
      echo "!!! mount exists ($IMG).  Please unmount first."
   fi
else
   mkdir $IMG
fi

mount -o loop $IMG.fs $IMG
if [ $? -ne 0 ] ; then 
   echo "!!!!!!!! mount failed.  Need to run as root or sudo"
   exit
fi
      
#extract contents from tar to disk file
echo "Untar file system"
tar -xzf $IMG-root.tar.gz -C $IMG
echo "Extract done"


cd $IMG
echo "Begin customizing image"
### fix the cloud image to work in XenServer
# add hvc0
sed -e 's/tty1/hvc0/g' etc/init/tty1.conf > etc/init/hvc0.conf
# fix disk label
sed -i.bak 's|LABEL=cloudimg-rootfs|/dev/xvda|g' boot/grub/menu.lst etc/fstab boot/grub/grub.cfg
# switch to ext3 -- adjust this if changed above
sed -i 's/ext4/ext3/' etc/fstab
# fix for ubuntu issue on XenServer <= 6.0
# see http://invalidlogic.com/2012/04/28/ubuntu-precise-on-xenserver-disk-errors/
sed -i 's/defaults/noatime,nodiratime,errors=remount-ro,barrier=0/' etc/fstab

### Cloud-init
#update default cloud.cfg to set a pw for ubuntu user and allow password authentication
sed -i.bak 's/user: ubuntu/user: ubuntu\npassword: passw0rd\nchpasswd: { expire: False }\nssh_pwauth: True\ndatasource_list: ["NoCloud", "CloudStack"]/' etc/cloud/cloud.cfg
#Remove other datasources from cloud init (can improve start-up time) and add CloudStack 
#  previous default list is: datasource_list: [ NoCloud, ConfigDrive, OVF, MAAS ]
echo "datasource_list: [ CloudStack ]" > etc/cloud/cloud.cfg.d/90_dpkg.cfg
#Replace broken cloud-init CloudStack DataSource 
test -f ../DataSourceCloudStack.py && cp ../DataSourceCloudStack.py usr/share/pyshared/cloudinit/
rm usr/lib/python2.7/dist-packages/cloudinit/DataSourceCloudStack.pyc

### Enable CloudStack Password set script
wget https://github.com/shankerbalan/cloudstack-scripts/raw/master/cloud-set-guest-password-ubuntu
chmod +x cloud-set-guest-password-ubuntu
mv cloud-set-guest-password-ubuntu etc/init.d/cloud-set-guest-password
#still need to enable startup script -- will do below in chroot

cd ..

#####
## Do any customizations you want here.
## Please note that for chroot to work best you should be running this on ubuntu 12.04

# mounts for chroot
mount -o bind /dev $IMG/dev 
mount -t proc /proc $IMG/proc
mount -o bind /sys $IMG/sys
# copy resol.conf to have DNS in chroot
cp /run/resolvconf/resolv.conf $IMG/run/resolvconf/resolv.conf
# copy xen guest utils -- you can get it from another instance that you have attached the 
test -f xe-guest-utilities_6.0.2-766_amd64.deb && cp xe-guest-utilities_6.0.2-766_amd64.deb $IMG/tmp

# create ec2-user, add to sudoers, set CS password script to start, install xen guest tools
chroot $IMG /bin/bash -x <<'EOF'
PASSWD=`openssl passwd -crypt passw0rd`
/usr/sbin/useradd ec2-user -m -p $PASSWD
echo -e 'ec2-user\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers
update-rc.d cloud-set-guest-password defaults
test -f /tmp/xe-guest-utilities_6.0.2-766_amd64.deb && dpkg -i /tmp/xe-guest-utilities_6.0.2-766_amd64.deb
/etc/init.d/xe-linux-distribution stop
EOF
# clean up resolv.conf
rm $IMG/run/resolvconf/resolv.conf

umount $IMG/{sys,proc,dev}

#####

umount $IMG
echo "Done creating image. You can mount it to check it out using:"
echo "mount -o loop $IMG.fs $IMG"
echo -e "\n If you are happy with it, copy $IMG.fs to one of your XenServer hosts and create the vhd file using createVHD.sh"

exit

