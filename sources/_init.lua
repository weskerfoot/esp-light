-- Never change these unless the board changes
red = 7
green = 5

pins = {toggle_red=red, toggle_green=green}
lights = {}
lights[green] = false
lights[red] = false

function calc_duty_cycle(duty_cycle_factor)
  if duty_cycle_factor <= 1 then
    return 1023
  else
    return 1023 / duty_cycle_factor
  end
end

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
  if is_table(12) or (not is_table({green=12})) then
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

function make_timer(params)
  -- interval is in milliseconds
  -- pin is the gpio number
  -- params {pin=pin, frequency=frequency, duty_cycle=duty_cycle, step=step, interval=interval, delay=delay}

  local duty_cycle_t = params["duty_cycle"]
  local direction = params["step"]
  local delay = 0
  print("timer created!")
  print(duty_cycle_t)
  local timer = tmr.create()
  timer:register(params["interval"], tmr.ALARM_AUTO, function()
    if delay > 0 then
      delay = delay - 1
      return
    end

    if (direction > 0 and ((duty_cycle_t + direction) >= 1023))  then
      delay = params["delay"]
      direction = -math.abs(direction)
    end

    if ((direction <= 0) and ((duty_cycle_t + direction) < 0)) then
      delay = params["delay"]
      direction = math.abs(direction)
    end

    if delay > 0 then
      return
    end

    duty_cycle_t = duty_cycle_t + direction

    -- if this is running then it's turned on
    lights[params["pin"]] = true
    pwm.setduty(params["pin"], duty_cycle_t)
  end)
  return timer
end

-- pwm.setup(pin, frequency, duty cycle) -- max duty cycle is 1023, min 1
pwm.setup(green, 500, 1023)
pwm.setup(red, 500, 1023)
pwm.start(green)
pwm.start(red)

timers = {red=false, green=false}

-- cron job which checks if auto mode is enabled
-- if auto mode is enabled, it cycles through various timers
-- runs the current timer for one period (cron job runs once every period of time)
-- then stops and unregisters that timer, and moves on to the next, etc
-- if auto mode is disabled, it does nothing
-- UI allows you to configure auto mode period maybe
-- UI could also allow to configure the specific settings but this might be too much work

auto_mode_enabled = true

function make_timer_params(pin, duty_cycle, interval, frequency, step, delay)
  duty_cycle = duty_cycle or 1023
  interval = interval or 20
  step = step or 1
  frequency = frequency or 500
  delay = delay or 200
  return {pin=pin, frequency=frequency, duty_cycle=duty_cycle, step=step, interval=interval, delay=delay}
end

function unregister_timers()
  if timers[green] then
    timers[green]:unregister()
  end
  if timers[red] then
    timers[red]:unregister()
  end
  duty_cycle = 1023
  pwm.setduty(red, duty_cycle)
  pwm.setduty(green, duty_cycle)
end

timer_states = {
          {green=make_timer_params(green, 1022, 200, 1000, 1021, 5), red=make_timer_params(red, 1022, 200, 1000, -1021, 5)},
          {green=make_timer_params(green, 1023, 5), red=make_timer_params(red, 1, 5)},
          --{green=make_timer_params(green, 1022, 100, 1000, -1021, 5), red=make_timer_params(red, 1022, 100, 1000, 1021, 5)},
          --{green=make_timer_params(green, 1023, 5, 1000), red=make_timer_params(red, 1, 5, 1000)},
          --{green=make_timer_params(green, 1023, 5), red=make_timer_params(red, 1023, 5)},
          --{green=make_timer_params(green, 1, 5), red=make_timer_params(red, 1023, 5)},
          --{green=make_timer_params(green, 1), red=make_timer_params(red, 1023)},
        }

function start_auto_mode()
  -- this is enabled by default
  local current_state = 1
  local number_of_states = table.getn(timer_states)
  print("Making cronjob, number of states = " .. number_of_states)
  cron.reset()
  unregister_timers()
  cron.schedule("*/1 * * * *", function(e)
    if auto_mode_enabled then
      print("Auto mode enabled, switching modes, current mode = " .. current_state)

      unregister_timers()

      -- TODO iter8 thru them instead
      timers[green] = make_timer(timer_states[current_state]["green"])
      timers[red] = make_timer(timer_states[current_state]["red"])
      timers[green]:start()
      timers[red]:start()

      current_state = (current_state % number_of_states) + 1

    end
  end)
end

function turn_light_on(pin, duty_cycle)
  if not lights[pin] and not auto_mode_enabled then
    lights[pin] = true
    pwm.setduty(pin, duty_cycle)
  end
end

function turn_light_off(pin)
  if lights[pin] and not auto_mode_enabled then
    pwm.setduty(pin, 0)
    lights[pin] = false
  end
end

function toggle_light(pin)
  if auto_mode_enabled then
    return
  end
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
        start_auto_mode()
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
            if params["toggle_mode"] == "mode_manual" then
              unregister_timers()
              auto_mode_enabled = false
            elseif params["toggle_mode"] == "mode_auto" then
              start_auto_mode()
              auto_mode_enabled = true
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

            local toggle_mode = gen_form("Toggle Mode", "toggle_mode", {["mode_manual"]="Manual", ["mode_auto"]="Auto"}, gen_select)
            local toggle_lights_form = gen_form("Toggle Lights Form", "toggle", {["toggle_red"]="Red", ["toggle_green"]="Green"}, gen_select)

            res:send("<style>.button{text-decoration:underline;}.body{padding:0; margin:0;}.par{display:flex;flex-direction:row;}.a{margin: auto;width:50%;}.b{margin: auto;width:50%;}</style><html><body><div class='par'><div class='a'><span>Uptime: ".. tostring(tmr.time()) .. " seconds</span>" .. toggle_lights_form .. toggle_mode .. "</div><div class='b'>" .. get_info("hw") .. get_info("build_config") .. get_info("sw_version") .. show_list(timer_states) .. "</div></div></body></html>")
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
