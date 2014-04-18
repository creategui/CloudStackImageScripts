#!/bin/bash

fail() {
   echo -e "\n!!!!!!!!!!: error: $?\n$1\n"
   exit $?
}

get_abs_filename() {
   # $1 : relative filename
   echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

if [ $# -ne 2 ]; then
   echo -e "\nUsage: $0 [vhd file] [mountpoint]\n"
   exit 1
fi

MOUNTPT=$2
VHD=`get_abs_filename $1`

test -e $VHD || fail "VHD file '$1' does not exist."
test -d $MOUNTPT || fail "'$2' does not exist or is not a directory."


# Check for vhd-util installation
dpkg-query -l blktap-utils >> /dev/null
test $? -ne 0 && fail "Please install blktap-utils (sudo apt-get install blktap-utils).\nProvides vhd-util which is required"


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

#mount disk file
mount $TAPDEV $MOUNTPT
test $? -ne 0 && fail "mount $TAPDEV $MOUNTPT failed."

echo -e "\nMount Successful.  To unmount use ./unmountVHD"
