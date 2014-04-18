#!/bin/bash

# 10 GB image
IMGSIZE=10240

fail() {
	echo -e "\n!!!!!!!!!! error\n$1\n"
	exit $?
}


# Check for root
test "$(id -u)" != "0" && fail "Requires running as root in order to mount."

# Check for vhd-util installation
dpkg-query -l blktap-utils
test $? -ne 0 && fail "Please install blktap-utils (sudo apt-get install blktap-utils).\nProvides vhd-util which is required"

### Create Ubuntu 12.04 raw disk file for Xen from cloud-images.ubuntu.com images
# http://cloud-images.ubuntu.com/releases/precise/release/

## Make sure to use root tar file
LINK=http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-amd64-root.tar.gz
FILE=${LINK##*/}
IMG=${FILE%-*}
VHD=`pwd`/$IMG.vhd

#Download file if not already
if [ ! -e "$FILE" ] ; then
   echo "Downloading Cloud Image Root tar"
   wget $LINK
   test $? -ne 0 && fail "!!!!!!!! Download failed ($LINK)."
else
   echo "Using existing Cloud Image Root tar:"
   ls -l $FILE
	 echo ""
fi

#create vhd file
test -e "$VHD" && fail "Disk File $VHD exists. Please move/delete it and try again for a clean run."

echo "Create $VHD disk file"
vhd-util create -n $VHD -s $IMGSIZE
test $? -ne 0 && fail "Unable to create $VHD"

#attach vhd file to blktap
TAPDEV=`tap-ctl allocate`
test $? -ne 0 && fail "tap-ctl: Unable to allocate tapdev"
TAPID=${TAPDEV: -1}
echo "Created tapdev: $TAPDEV with id: $TAPID"
TAPPID=`tap-ctl spawn`
test $? -ne 0 && fail "tap-ctl: Unable to spawn tapdisk"
echo "Spawned tapdisk pid: $TAPPID"
tap-ctl attach -m $TAPID -p $TAPPID
test $? -ne 0 && fail "tap-ctl: Unable to attach tapdev to tapdisk"
echo "Attached $TAPDEV to process $TAPPID"
tap-ctl open -m $TAPID -p $TAPPID -a vhd:$VHD
test $? -ne 0 && fail "tap-ctl: Unable to open $VHD"

#make filesystem
mke2fs -F -j $TAPDEV
test $? -ne 0 && fail "Unable to create ext3 fs in $TAPDEV"

#mount disk file
mount | grep $IMG
test $? -eq 0 && fail "!!! mount exists ($IMG).  Please unmount first."
test -e "$IMG" || mkdir $IMG
test $? -ne 0 && fail "unable to create $IMG path"

mount $TAPDEV $IMG
test $? -ne 0 && fail "!!!!!!!! mount $TAPDEV failed."

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
#Patch broken cloud-init CloudStack DataSource
test -f ../DataSourceCloudStack.patch && patch -p1 <../DataSourceCloudStack.patch
rm usr/lib/python2.7/dist-packages/cloudinit/DataSourceCloudStack.pyc

### Enable CloudStack Password set script
wget -q https://github.com/shankerbalan/cloudstack-scripts/raw/master/cloud-set-guest-password-ubuntu
chmod +x cloud-set-guest-password-ubuntu
mv cloud-set-guest-password-ubuntu etc/init.d/cloud-set-guest-password
#still need to enable startup script -- will do below in chroot

cd ..

#####
## Do any customizations you want here.
## Please note that for chroot to work best you should be running this on ubuntu 12.04

#if xen guest utils running stop them first.  this is an attempt to make the umount later work.
test -f /etc/init.d/xe-linux-distribution && /etc/init.d/xe-linux-distribution stop
sleep 5

# mounts for chroot
mount -o bind /dev $IMG/dev
mount -t proc /proc $IMG/proc
mount -o bind /sys $IMG/sys
# copy resol.conf to have DNS in chroot
mkdir -p $IMG/run/resolvconf
cp /run/resolvconf/resolv.conf $IMG/run/resolvconf/resolv.conf
# copy xen guest utils -- you can get it from another instance that you have attached the
test -f xe-guest-utilities_6.0.2-766_amd64.deb && cp xe-guest-utilities_6.0.2-766_amd64.deb $IMG/tmp

# create ec2-user, add to sudoers, set CS password script to start, install xen guest tools
chroot $IMG /bin/bash -x <<'EOF'
locale-gen en_US en_US.UTF-8
dpkg-reconfigure locales
PASSWD=`openssl passwd -crypt passw0rd`
/usr/sbin/useradd ec2-user -m -p $PASSWD
echo -e 'ec2-user\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers
update-rc.d cloud-set-guest-password defaults
test -f /tmp/xe-guest-utilities_6.0.2-766_amd64.deb && dpkg -i /tmp/xe-guest-utilities_6.0.2-766_amd64.deb
/etc/init.d/xe-linux-distribution stop
sleep 5
rm /run/resolvconf/resolv.conf
exit 0
EOF
#above sleep is in hope for umount below to work.

# clean up resolv.conf
#rm $IMG/run/resolvconf/resolv.conf

# Not sure what else to try to get dev and proc to unmount
MNTS="sys dev proc"
for MNT in $MNTS; do
		umount -f $IMG/$MNT
		if [ $? -ne 0 ]; then
				sleep 5
				echo "trying lazy: umount -l $IMG/$MNT."
				umount -l $IMG/$MNT
		fi
done
sleep 5

# restart xen guest utils
test -f /etc/init.d/xe-linux-distribution && /etc/init.d/xe-linux-distribution start

#####

umount $IMG
test $? -ne 0 && fail "Unable to unmount vhd\nCheck mount and clean up sys/dev/proc if still mounted\nthen: ./unmountVHD.sh $IMG.vhd"

# clean up tapdev
tap-ctl close -m $TAPID -p $TAPPID
test $? -ne 0 && fail "tap-ctl: Unable to close tapdisk"
tap-ctl detach -m $TAPID -p $TAPPID
test $? -ne 0 && fail "tap-ctl: Unable to detach tapdev"
tap-ctl free -m $TAPID
test $? -ne 0 && fail "tap-ctl: Unable to free tapdev"

echo "Done creating image. You can mount it to check it out using mountVHD.sh script."
echo "./mountVHD $IMG.vhd"
echo -e "\n If you are happy with it, copy $IMG.vhd to a webserver that Cloudstack can fetch it from."
echo "you can also compress it prior to copying it with:"
echo "bzip2 -c $IMG.vhd > $IMG.vhd.bz2"
exit 0
