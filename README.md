Lua code, scripts, and firmware for my smart light project.

## How to use
You can flash this to your esp8266 (with nodemcu on it), change the pin numbers correspondingly, and it should work.

It has a relay attached to it that switches a light on/off depending on the voltage, as well as a temperature sensor connected to the ADC (analog-digital converter) pin, which is used to handle motion detection using a sonar sensor. You can modify the code according to whatever hardware you have.

The main useful thing here is the code for getting reliable sonar readings, which take several samples and average them, and use the standard error to try and make it more accurate. It also uses the temperature to calculate the speed of sound, which varies depending on the temperature and air humidity.

Hardware used:

* https://www.adafruit.com/product/3942
* https://learn.adafruit.com/adafruit-power-relay-featherwing
* https://www.nodemcu.com/index_en.html
* https://www.adafruit.com/product/165
