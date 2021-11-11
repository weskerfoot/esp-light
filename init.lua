-- Never change these unless the board changes
echo_pin = 2
trig_pin = 3
light_pin = 5

use_sonar = false
light_on = false

if adc.force_init_mode(adc.INIT_ADC)
then
  node.restart()
  return -- don't bother continuing, the restart is scheduled
end

print("System voltage (mV):", adc.readvdd33(0))

gpio.mode(light_pin, gpio.OUTPUT)
gpio.mode(echo_pin, gpio.INT) -- interrupt mode
gpio.mode(trig_pin, gpio.OUTPUT)
gpio.write(light_pin, gpio.HIGH)

function toggle_light()
  if light_on then
    gpio.write(light_pin, gpio.HIGH)
  else
    gpio.write(light_pin, gpio.LOW)
  end
  light_on = not light_on
end

function turn_light_on()
  gpio.write(light_pin, gpio.LOW)
end

function turn_light_off()
  gpio.write(light_pin, gpio.HIGH)
end

function tablelen(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

samples = {}
distance = {start_v=0.0, end_v=0.0}

sample_rate = 4 -- number of samples it requires before triggering, recommended <= 5, >=3
max_stderr = 0.5 -- margin of error allowed before triggering the light, recommended <= 1
distance_max = 30 -- threshold for how far an object must be to trigger it in cm
distance_min = 10 -- minimum distance (below this amount don't trigger it), recommended >= 5, <= 20

-- Get the mean value of a table
function mean(t)
  -- http://lua-users.org/wiki/SimpleStats
  local sum = 0
  local count = 0

  for k,v in pairs(t) do
    if type(v) == 'number' then
      sum = sum + v
      count = count + 1
    end
  end
  return (sum / count)
end

function stdev(t)
  -- http://lua-users.org/wiki/SimpleStats
  local m
  local vm
  local sum = 0
  local count = 0
  local result

  m = mean(t)

  for k, v in pairs(t) do
    if type(v) == 'number' then
      vm = v - m
      sum = sum + (vm * vm)
      count = count + 1
    end
  end

  result = math.sqrt(sum / (count-1))

  return result
end

function stderr(t)
  -- based on the definition of standard error
  return stdev(t) / math.sqrt(tablelen(t))
end

function measure(level, ts, evcount)
  if level == 1 then
    distance["start_v"] = ts
  else
    -- check if there's a low voltage but no starting high voltage
    if distance["start_v"] > 0 then
      distance["end_v"] = ts

      if distance["start_v"] >= distance["end_v"] then
        distance = {start_v=0.0, end_v=0.0} -- bad reading
        return
      end

      -- See https://www.adafruit.com/product/165
      local temperature = ((adc.read(0)*100)-50)/1000

      -- See http://hyperphysics.phy-astr.gsu.edu/hbase/Sound/souspe.html
      local speed_of_sound = (331.4 + 0.6*temperature)/10000

      -- See https://randomnerdtutorials.com/esp8266-nodemcu-hc-sr04-ultrasonic-arduino/
      local d = ((distance["end_v"] - distance["start_v"]) * speed_of_sound) / 2.0

      -- Only care about values between 10 and 50
      if math.floor(d) > distance_min and d < distance_max then
        table.insert(samples, d)
        local s = stderr(samples)
        if s > max_stderr and tablelen(samples) == (sample_rate - 1) then -- start over if it would cause stderr to be too great
          samples = {}
          distance = {start_v=0.0, end_v=0.0}
        end

      end
      distance = {start_v=0, end_v=0}
    end
  end

  local s_num = tablelen(samples)

  if s_num >= sample_rate then
    local distance_mean = mean(samples)
    local s = stderr(samples)
    if s < max_stderr and distance_mean < distance_max and distance_mean > distance_min then
      print("stder = " .. s)
      print("distance = " .. distance_mean)
      if not light_on then
        toggle_light()
      end
    end
    samples = {}
  end
end

function trig()
  gpio.write(trig_pin, gpio.HIGH)
  tmr.delay(11)
  gpio.write(trig_pin, gpio.LOW)
end

-- load credentials, 'SSID' and 'PASSWORD' declared and initialize in there
dofile("credentials.lua")

function startup()

    if file.open("init.lua") == nil then
        print("init.lua deleted or renamed")
    else
        print("Running")
        file.close("init.lua")

        print("Starting up")
        sntp.sync(nil,
          function(sec, usec, server, info)
            print("sync'd")

            tm = rtctime.epoch2cal(rtctime.get())

            print(tm["hour"])
            print(tm["min"])

            if tm["hour"] >= 12 or tm["hour"] < 2 then
              if tm["hour"] == 12 and tm["min"] < 30 then
                return
              end
              turn_light_on()
            end

            if tm["hour"] >= 2 and tm["hour"] < 12 then
              turn_light_off()
            end

            cron.schedule("0 02 * * *", function(e) -- 9 pm EST is 2 UTC
              print("Turning light off")
              turn_light_off()
            end)

            cron.schedule("30 12 * * *", function(e) -- 7:30 am EST is 12:30 UTC
              print("Turning light on")
              turn_light_on()
            end)

            if use_sonar then
              tmr.create():alarm(61, tmr.ALARM_AUTO, trig)
              gpio.trig(echo_pin, "both", measure)
            end
          end,
        nil, 1)

        require("httpserver").createServer(80, function(req, res)
          print("+R", req.method, req.url, node.heap())

          req.onheader = function(self, name, value) -- luacheck: ignore
            print("+H", name, value)
          end
          -- setup handler of body, if any
          req.ondata = function(self, chunk) -- luacheck: ignore
            print("+B", chunk and #chunk, node.heap())
            print(req.url)
            if not chunk then
              -- reply
              res:send(nil, 200)
              res:send_header("Connection", "close")
              if req.url == "/toggle" then
                toggle_light()
              elseif req.url == "/on" then
                turn_light_on()
              elseif req.url == "/off" then
                turn_light_off()
              elseif req.url == "/toggle_sonar" then
                use_sonar = not use_sonar
              end

              res:send("The light is " .. (light_on and "on\n" or "off\n"))
              res:finish()
            end
          end
        end)

    end
end

-- Define WiFi station event callbacks
wifi_connect_event = function(T)
  print("Connection to AP("..T.SSID..") established!")
  print("Waiting for IP address...")
  if disconnect_ct ~= nil then disconnect_ct = nil end
end

wifi_got_ip_event = function(T)
  -- Note: Having an IP address does not mean there is internet access!
  -- Internet connectivity can be determined with net.dns.resolve().
  print("Wifi connection is ready! IP address is: "..T.IP)
  print("Startup will resume momentarily, you have 3 seconds to abort.")
  print("Waiting...")
  tmr.create():alarm(3000, tmr.ALARM_SINGLE, startup)
  mdns.register("smartlight", {hardware='NodeMCU'})
end

wifi_disconnect_event = function(T)
  if T.reason == wifi.eventmon.reason.ASSOC_LEAVE then
    --the station has disassociated from a previously connected AP
    return
  end
  -- total_tries: how many times the station will attempt to connect to the AP. Should consider AP reboot duration.
  local total_tries = 75
  print("\nWiFi connection to AP("..T.SSID..") has failed!")

  --There are many possible disconnect reasons, the following iterates through
  --the list and returns the string corresponding to the disconnect reason.
  for key,val in pairs(wifi.eventmon.reason) do
    if val == T.reason then
      print("Disconnect reason: "..val.."("..key..")")
      break
    end
  end

  if disconnect_ct == nil then
    disconnect_ct = 1
  else
    disconnect_ct = disconnect_ct + 1
  end
  if disconnect_ct < total_tries then
    print("Retrying connection...(attempt "..(disconnect_ct+1).." of "..total_tries..")")
  else
    wifi.sta.disconnect()
    print("Aborting connection to AP!")
    disconnect_ct = nil
  end
end

-- Register WiFi Station event callbacks
wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, wifi_connect_event)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_got_ip_event)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, wifi_disconnect_event)

print("Connecting to WiFi access point...")
wifi.setmode(wifi.STATION)
wifi.sta.config({ssid=SSID, pwd=PASSWORD})
-- wifi.sta.connect() not necessary because config() uses auto-connect=true by default
