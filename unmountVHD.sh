#!/bin/bash

fail() {
  echo -e "\n!!!!!!!!!!: error: $?\n$1\n"
  exit $?
}

get_abs_filename() {
  # $1 : relative filename
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Check for vhd-util installation
dpkg-query -l blktap-utils >> /dev/null
test $? -ne 0 && fail "Please install blktap-utils (sudo apt-get install blktap-utils).\nProvides vhd-util which is required"

#check usage
if [ $# -ne 1 ]; then
   echo -e "\nUsage: $0 [vhd file]\n"
   exit 1
fi

VHD=`get_abs_filename $1`

test -e $VHD || fail "VHD file '$1' does not exist."
tmp=`tap-ctl list | grep $VHD`
test $? -ne 0 && fail "VHD file $VHD not mounted"
for kv in $tmp; do
   key=${kv%%=*}
   value=${kv##*=}
   eval TAP$key=$value
done

TAPDEV=/dev/xen/blktap-2/tapdev$TAPminor

mount | grep $TAPDEV
if [ $? -ne 0 ]; then
   echo -e "$TAPDEV not mounted for $VHD.\nWill continue tap-ctl cleanup."
else
   umount $TAPDEV
   test $? -ne 0 && fail "umount failed for $TAPDEV"
fi

# clean up tapdev
tap-ctl close -m $TAPminor -p $TAPpid
test $? -ne 0 && fail "tap-ctl: Unable to close tapdisk"
tap-ctl detach -m $TAPminor -p $TAPpid
test $? -ne 0 && fail "tap-ctl: Unable to detach tapdev"
tap-ctl free -m $TAPminor
test $? -ne 0 && fail "tap-ctl: Unable to free tapdev"

echo -e "\nUnmount successful"
exit 0
