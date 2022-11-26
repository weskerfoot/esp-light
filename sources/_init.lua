-- Never change these unless the board changes
red = 7
green = 5

pins = {toggle_red=red, toggle_green=green}
lights = {}
lights[green] = false
lights[red] = false

-- cron job which checks if auto mode is enabled
-- if auto mode is enabled, it cycles through various timers
-- runs the current timer for one period (cron job runs once every period of time)
-- then stops and unregisters that timer, and moves on to the next, etc
-- if auto mode is disabled, it does nothing
-- UI allows you to configure auto mode period maybe
-- UI could also allow to configure the specific settings but this might be too much work

function display_table(t)
  print("table")
  for k, v in pairs(t) do
    print("k = " .. tostring(k), ", v = " .. tostring(v))
  end
end

function calc_duty_cycle(duty_cycle_factor)
  if duty_cycle_factor <= 1 then
    return 1023
  else
    return 1023 / duty_cycle_factor
  end
end

function make_timer(pin, interval, initial_duty_cycle)
  -- interval is in milliseconds
  -- pin is the gpio number
  local duty_cycle_t = initial_duty_cycle
  local direction = 1
  local delay = 0
  print("timer created!")
  local timer = tmr.create()
  timer:register(interval, tmr.ALARM_AUTO, function()
    if delay > 0 then
      delay = delay - 1
      return
    end

    if duty_cycle_t >= 1023 then 
      delay = 200
      direction = -1
    elseif duty_cycle_t <= 0 then
      delay = 200
      direction = 1
    end

    duty_cycle_t = duty_cycle_t + direction

    if delay > 0 then
      return
    end

    -- if this is running then it's turned on
    lights[pin] = true
    pwm.setduty(pin, duty_cycle_t)
  end)
  return timer
end

-- pwm.setup(pin, frequency, duty cycle) -- max duty cycle is 1023, min 1
pwm.setup(green, 500, 1023)
pwm.setup(red, 500, 1023)
pwm.start(green)
pwm.start(red)

timers = {}
timers[green] = make_timer(green, 10, 1)
timers[red] = make_timer(red, 10, 1023)
timers[green]:stop()
timers[red]:stop()

function turn_on_fade(pin)
  timers[pin]:start()
end

function turn_light_on(pin, duty_cycle)
  if not lights[pin] then
    lights[pin] = true
    pwm.setduty(pin, duty_cycle)
  end
end

function turn_light_off(pin)
  if lights[pin] then
    pwm.setduty(pin, 0)
    lights[pin] = false
  end
end

function toggle_light(pin)
  print("Toggling " .. tostring(pin))
  local duty_cycle = calc_duty_cycle(1)
  print("duty_cycle = ".. duty_cycle)
  if lights[pin] then
    turn_light_off(pin)
  else
    turn_light_on(pin, duty_cycle)
  end
end

print("Booted up")

function hex_to_char(x)
  return string.char(tonumber(x, 16))
end

function get_time()
  local t = tmr.time()
  local hours = t/3600
  local seconds_leftover = t % 3600
  return tostring(hours) .. " hours, " .. tostring(minutes_leftover)
end

function urldecode(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end

function extract_formdata(s)
  local cgi = {}
  for name, value in string.gmatch(s, "([^&=]+)=([^&=]+)") do
    cgi[name] = value
  end
  return cgi
end

function get_info(group)
  local info = node.info(group)
  local result = "<table><thead><tr><th colspan='2'>" .. tostring(group) .. "</th></thead><tbody>"
  for key, value in pairs(info) do
    result = result .. "<tr><td>" .. tostring(key) .. "</td><td>" .. tostring(value) .. "</td></tr>"
  end

  return result .. "</tbody></table>"
end

function compose(f, g)
  return function(x) f(g(x)) end
end

function gen_select(name, id, options)
  local result = "<label for='" .. id .. "'>" .. name .. "</label><select name='" .. id .. "' id='" .. id .. "'>"
  for key, value in pairs(options) do
    result = result .. "<option value='" .. key .. "'>" .. value .. "</option>"
  end
  return result .. "</select>"
end

function gen_form(name, endpoint, fields, gen_inputs)
  local result = "<h2>" .. name .. "</h2><form action='/" .. endpoint .. "' method='post'>"
  result = result .. gen_inputs(name, endpoint, fields)
  return result .. "<div class='form-example'><input type='submit' value='Submit'></div></form>"
end

function gen_buttons(name, endpoint, fields)
  local result = "<h2>" .. name .. "</h2>"
  for key, value in pairs(fields) do
    result = result .. "<form action='/" .. key .. "' method='post'>"
    result = result .. "<button style='color:black;'>" .. value .. "</button><span style='color:black;'>" .. "status here" .. "</span></form>"
  end
  return result
end

function startup()
    sntp.sync(
      nil,
      function(sec, usec, server, info)
        print('synced ntp ', sec, usec, server)
      end,
      function()
        print('failed to sync ntp')
      end,
      1 -- auto-repeat sync
    )
    file.close("_init.lua")
    print("Starting up")
    local httpserver = node.LFS.get("httpserver")()
    print(httpserver)

    httpserver.createServer(8080, function(req, res)
      --print("+R", req.method, req.url, node.heap())

      req.ondata = function(self, chunk)
        --print("+B", chunk and #chunk, node.heap())
        print(req.url)
        if chunk ~= nil then
          if req.url == "/toggle" then
            local params = extract_formdata(urldecode(chunk))
            if params["toggle"] ~= nil then
              toggle_light(pins[params["toggle"]])
            end
          elseif req.url == "/toggle_mode" then
            local params = extract_formdata(urldecode(chunk))
            display_table(params)
            if params["toggle_mode"] == "mode_manual" then
              timers[green]:stop()
              timers[red]:stop()
            elseif params["toggle_mode"] == "mode_fade" then
              timers[green]:start()
              timers[red]:start()
            end
          elseif req.url == "/reboot" then
            node.restart()
          end
        end
        if not chunk then
          -- reply
          if req.url == "/" then
            res:send(nil, 200)
            res:send_header("Content-Type", "text/html")
            res:send_header("Connection", "close")

            local toggle_mode = gen_form("Toggle Mode", "toggle_mode", {["mode_fade"]="Fade", ["mode_manual"]="Manual"}, gen_select)
            local toggle_lights_form = gen_form("Toggle Lights Form", "toggle", {["toggle_red"]="Red", ["toggle_green"]="Green"}, gen_select)

            res:send("<style>.button{text-decoration:underline;}.body{padding:0; margin:0;}.par{display:flex;flex-direction:row;}.a{margin: auto;width:50%;}.b{margin: auto;width:50%;}</style><html><body><div class='par'><div class='a'><span>Uptime: ".. tostring(tmr.time()) .. " seconds</span>" .. toggle_lights_form .. toggle_mode .. "</div><div class='b'>" .. get_info("hw") .. get_info("build_config") .. get_info("sw_version") .. "</div></div></body></html>")
            res:send("\r\n")
          elseif req.url == "/toggle" then
            res:send(nil, 303)
            res:send_header("Location", "/")
            res:send_header("Connection", "close")
            res:send("switching light\r\n")
            res:send("\r\n")
          else
            res:send(nil, 303)
            res:send_header("Location", "/")
            res:send_header("Connection", "close")
            res:send("\r\n")
          end
          res:finish()
        end
      end

    end)
end

function connect_wifi()
    print("Trying to connect to wifi with captive portal")
    wifi.sta.disconnect()
    -- wifi.sta.clearconfig()
    enduser_setup.start(
    function()
      if wifi.sta.getip() ~= nil then 
        print("Connected to WiFi as:" .. wifi.sta.getip())
        tmr.create():alarm(3000, tmr.ALARM_SINGLE, startup)
      end
    end,
    function(err, str)
      print("enduser_setup: Err #" .. err .. ": " .. str)
    end,
    print
  )
end

connect_wifi()
