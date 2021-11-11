nodemcu-tool reset
esptool.py erase_flash
esptool.py --port /dev/ttyUSB0 write_flash -fm qio 0x00000 firmware/nodemcu-release-19-modules-2021-11-10-19-19-06-float.bin

nodemcu-tool upload *.lua libs/*

while [[ $? != 0 ]]; do
  nodemcu-tool upload *.lua libs/*
done

echo 'dofile("init.lua")' | nodemcu-tool terminal
