#! /usr/bin/env bash

#while read f; do /home/wes/code/nodemcu-firmware/luac.cross.int -o "$(echo $f | cut -d '.' -f 1).lc" $f ; done < <(ls *lua)
#rm -f init.lc

rm -f lfs.img
/home/wes/code/nodemcu-firmware/luac.cross.int -f -o lfs.img *lua
