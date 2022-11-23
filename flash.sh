rm firmware/*bin
cp /home/wes/code/nodemcu-firmware/bin/*bin ./firmware
rm -f sources/lfs.img
cd sources && ./compile.sh
cd ../

nodemcu-tool reset
function reset_flash() {
  nodemcu-tool reset
  esptool.py --port /dev/ttyUSB0 erase_flash
  esptool.py --port /dev/ttyUSB0 write_flash -fm dio 0x00000 firmware/0x00000.bin
  esptool.py --port /dev/ttyUSB0 write_flash -fm dio 0x10000 firmware/0x10000.bin
}

#reset_flash

CONN_DELAY=1000

nodemcu-tool --connection-delay $CONN_DELAY remove lfs.img
nodemcu-tool --connection-delay $CONN_DELAY upload sources/lfs.img

while [[ $? != 0 ]]; do
  nodemcu-tool --connection-delay $CONN_DELAY upload sources/lfs.img
done
#
echo 'print(node.LFS.reload("lfs.img"))' | nodemcu-tool --connection-delay $CONN_DELAY terminal
nodemcu-tool --connection-delay $CONN_DELAY remove lfs.img
nodemcu-terminal
