nodemcu-tool reset
esptool.py erase_flash
esptool.py --port /dev/ttyUSB0 write_flash -fm qio 0x00000 firmware/nodemcu-release-16-modules-2021-10-09-22-33-53-float.bin

nodemcu-tool upload *.lua libs/*

while [[ $? != 0 ]]; do
  nodemcu-tool upload *.lua libs/*
done

echo 'dofile("init.lua")' | nodemcu-tool terminal
