-- Never change these unless the board changes
started = false
light_pin = 5
motion_pin = 7

--turn_off_timeout = 1000*60*1 -- for turning off if it triggered via sensor
turn_off_timer = tmr.create()

timeout_settings = {["turn_off_timeout"]=1000*60*30, ["turn_off_timeout_minutes"]=30}

gpio.mode(motion_pin, gpio.INT)

function set_turn_off_timeout(new_timeout)
  if new_timeout > 0 and new_timeout < 1440 then
    timeout_settings["turn_off_timeout_minutes"] = new_timeout
    timeout_settings["turn_off_timeout"] = 1000*60*new_timeout
  end
end

function calc_duty_cycle(duty_cycle_factor)
  if duty_cycle_factor < 1 then
    return 0
  else
    return 1023 / duty_cycle_factor
  end
end

global_duty_cycle = calc_duty_cycle(1)

function debounce (func)
	local last = 0
	local delay = 500000

	return function (...)
		local now = tmr.now()
    local delta = now - last

    if delta < 0 then
      delta = delta + 2147483647
    end

		if delta < delay then
      return
    end

		last = now
		return func(...)
	end
end

-- pwm.setup(pin, frequency, duty cycle) -- max duty cycle is 1023, min 1
pwm.setup(light_pin, 500, 1023)
pwm.start(light_pin)

current_mode = nil

pins = {toggle_light_pin=light_pin}
lights = {}

if gpio.read(light_pin) == 1 then
  lights[light_pin] = true
else
  lights[light_pin] = false
end

function turn_light_on(pin, duty_cycle, reset_timeout)
  lights[pin] = true
  pwm.setduty(pin, duty_cycle)
  if reset_timeout then
    turn_off_timer:stop()
    turn_off_timer:unregister()
  end
end

function to_percent(a, b)
  return (a*b)/100
end

function get_duty_cycle_percentage(pin)
  local d = pwm.getduty(pin)
  return (d*100)/1023
end

function set_light_brightness(pin, percentage)
  --print("percentage = " .. tostring(percentage))
  local duty_cycle = to_percent(1023, percentage)
  --print("set light to " .. tostring(duty_cycle))
  pwm.setduty(pin, duty_cycle)
  global_duty_cycle = duty_cycle
  if duty_cycle > 0 then
    lights[pin] = true
  else
    lights[pin] = false
  end
end

function turn_light_off(pin)
  if lights[pin] then
    pwm.setduty(pin, 0)
    lights[pin] = false
  end
end

function toggle_light(pin)
  --print("Toggling " .. tostring(pin))
  if lights[pin] then
    turn_light_off(pin)
  else
    turn_light_on(pin, global_duty_cycle, true)
  end
end

function sensor_trigger_on(level, ts, evcount)
  if level == gpio.HIGH and gpio.read(light_pin) == 0 then
    --print("sensor pin is high")
    turn_light_on(light_pin, global_duty_cycle, true)
    turn_off_timer:register(timeout_settings["turn_off_timeout"], tmr.ALARM_SINGLE, function()
      turn_light_off(light_pin)
    end)
    turn_off_timer:start()
  end
end

gpio.trig(motion_pin, "up", sensor_trigger_on)

function is_table(v)
  local is_it_a_table, _ = pcall(function() return v["is_table"] end)
  return is_it_a_table
end

function show_pair(key, value)
  -- TODO handle case of array and then call back to show_list
  if is_table(value) then
    return "("..tostring(key) .. " . " .. tostring(show_table(value)) .. ")"
  else
    return "("..tostring(key) .. " . " .. tostring(value) .. ")"
  end
end

function show_table(t)
  result = ""
  for key, value in pairs(t) do
    result = result .. show_pair(key, value)
  end
  return "(" .. result .. ")"
end

function show_list(ts)
  if is_table(12) or (not is_table({light_pin=12})) then
    return ""
  end
  result = ""
  for _, t in ipairs(ts) do
    if is_table(t) then
      result = result .. show_table(t)
    else
      result = result .. tostring(t)
    end
  end
  return "(" .. result .. ")"
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
  local result = "<table class='table-auto'><thead><tr><th colspan='2'>" .. tostring(group) .. "</th></thead><tbody>"
  result = result .. "<tr><td>Uptime: ".. tostring(tmr.time()) .. " seconds</td></tr>"
  for key, value in pairs(info) do
    result = result .. "<tr><td>" .. tostring(key) .. "</td><td>" .. tostring(value) .. "</td></tr>"
  end

  return result .. "</tbody></table>"
end

function compose(f, g)
  return function(x) f(g(x)) end
end

function gen_select(name, id, options)
  local result = "<label class='m-1 px-2' for='" .. id .. "'>" .. name .. "</label><select name='" .. id .. "' id='" .. id .. "'>"
  for key, value in pairs(options) do
    result = result .. "<option class='p-1 px-2' value='" .. key .. "'>" .. value .. "</option>"
  end
  return result .. "</select>"
end

function gen_range_select(name, id, options)
  local min = options["min"]
  local max = options["max"]
  local value = options["value"]
  return "<label class='m-1 px-2' for='" .. id .. "'>" .. name .. "</label><input class='min-w-min p-1 px-2' type='range' name='" .. id .. "' id='" .. id .. "' value='" .. value .. "' min='" .. min .. "' max='" .. max .. "'></input>"
end

function gen_num_select(name, id, options)
  local min = options["min"]
  local max = options["max"]
  local value = options["value"]
  return "<label class='m-1 px-2' for='" .. id .. "'>" .. name .. "</label><input class='w-20 p-1 px-2' type='number' name='" .. id .. "' id='" .. id .. "' value='" .. value .. "' min='" .. min .. "' max='" .. max .. "'></input>"
end

function gen_form(form_name, name, endpoint, fields, gen_inputs)
  local result = "<div class='py-3 min-w-full'><h2 class='text-center font-serif text-lg'>" .. form_name .. "</h2><form class='py-8 text-center' action='/" .. endpoint .. "' method='post'>"
  result = result .. gen_inputs(name, endpoint, fields)
  return result .. "<input class='p-1 px-2 m-3 border-2 hover:bg-sky-100' type='submit' value='Submit'></form></div>"
end

function gen_buttons(name, endpoint, fields)
  local result = "<h2 class='text-center font-serif text-lg'>" .. name .. "</h2>"
  for key, value in pairs(fields) do
    result = result .. "<form class='py-8 text-center' action='/" .. key .. "' method='post'>"
    result = result .. "<button class='min-w-min p-1' style='color:black;'>" .. value .. "</button><span style='color:black;'>" .. "status here" .. "</span></form>"
  end
  return result
end

function startup()
    sntp.sync(
      nil,
      function(sec, usec, server, info)
        print('synced ntp ', sec, usec, server)
        if not started then
          started = true
        end
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
          elseif req.url == "/reboot" then
            node.restart()
          elseif req.url == "/set_brightness" then
            local params = extract_formdata(urldecode(chunk))
            if params["set_brightness"] ~= nil then
              local percentage = tonumber(params["set_brightness"])
              set_light_brightness(light_pin, percentage)
            end
          elseif req.url == "/set_timeout" then
            local params = extract_formdata(urldecode(chunk))
            if params["set_timeout"] ~= nil then
              local new_timeout = tonumber(params["set_timeout"])
              set_turn_off_timeout(new_timeout)
            end
          end
        end
        if not chunk then
          -- reply
          if req.url == "/" then
            res:send(nil, 200)
            res:send_header("Content-Type", "text/html")
            res:send_header("Connection", "close")

            local current_dc_percent = tostring(get_duty_cycle_percentage(light_pin))

            local toggle_lights_form = gen_form("Lights", "Toggle Lights", "toggle", {["toggle_light_pin"]="Light"}, gen_select)
            local set_brightness_form = gen_form("Brightness", "Set Brightness (%)", "set_brightness", {["min"]="0", ["max"]="100", ["value"]=current_dc_percent}, gen_range_select)
            local set_timeout_form = gen_form("Timeout", "Set Timeout (minutes)", "set_timeout", {["min"]="0", ["max"]="1440", ["value"]=timeout_settings["turn_off_timeout_minutes"]}, gen_num_select)

            res:send("<style>.button{text-decoration:underline;}</style><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'><script src='https://cdn.tailwindcss.com'></script></head><body><h1 class='text-xl text-center uppercase font-bold'>Light Config</h1><div class='wy-10 place-content-around grid md:grid-cols-2 gap-3'><div class='a border-solid border-2 justify-center items-center'>" .. toggle_lights_form .. set_brightness_form .. set_timeout_form .. "</div><div class='b justify-center border-solid border-2 items-center'>" .. get_info("hw") .. get_info("build_config") .. get_info("sw_version") .. "</div></div></body></html>")
            res:send("\r\n")
          elseif req.url == "/toggle" then
            res:send(nil, 303)
            res:send_header("Location", "/")
            res:send_header("Connection", "close")
            res:send("switching light\r\n")
            res:send("\r\n")
          elseif req.url == "/set_brightness" then
            res:send(nil, 303)
            res:send_header("Location", "/")
            res:send_header("Connection", "close")
            res:send("setting brightness\r\n")
            res:send("\r\n")
          elseif req.url == "/set_timeout" then
            res:send(nil, 303)
            res:send_header("Location", "/")
            res:send_header("Connection", "close")
            res:send("setting timeout\r\n")
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
    print("Turning lights off")

    if gpio.read(light_pin) == 1 then
      lights[light_pin] = true
    else
      lights[light_pin] = false
    end

    turn_light_off(light_pin)

    --wifi.sta.clearconfig()
    print("Trying to connect to wifi with captive portal")
    enduser_setup.start("Reading Light",
    function()
      print("in connection function")
      --print("Connected to WiFi as:" .. wifi.sta.getip())
      tmr.create():alarm(3000, tmr.ALARM_SINGLE, startup)
    end,
    function(err, str)
      print("enduser_setup: Err #" .. err .. ": " .. str)
    end,
    print
  )
end

connect_wifi()
