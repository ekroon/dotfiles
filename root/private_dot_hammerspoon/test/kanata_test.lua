local M = {}

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format(
      "%s: expected %s, got %s",
      message or "values should be equal",
      tostring(expected),
      tostring(actual)
    ), 2)
  end
end

local function assertTrue(value, message)
  if not value then error(message or "expected value to be truthy", 2) end
end

local function setupHs()
  local env = {
    afterTimers = {},
    menus = {},
    sockets = {},
  }

  local function timer(delay, callback)
    local value = {
      callback = callback,
      delay = delay,
      stopped = false,
    }
    function value:stop()
      self.stopped = true
    end
    return value
  end

  hs = {
    json = {
      decode = function(data)
        return env.events[data]
      end,
    },
    menubar = {},
    socket = {},
    timer = {},
  }
  env.events = {}

  hs.menubar.new = function()
    local menu = {}
    function menu:setTitle(title)
      self.title = title
    end
    function menu:setClickCallback(callback)
      self.click = callback
    end
    table.insert(env.menus, menu)
    return menu
  end

  hs.socket.new = function(callback)
    local socket = {
      callback = callback,
      connectedValue = false,
      reads = 0,
      writes = {},
    }
    function socket:connect(host, port, connectCallback)
      self.host = host
      self.port = port
      self.connectCallback = connectCallback
      return true
    end
    function socket:connected()
      return self.connectedValue
    end
    function socket:disconnect()
      self.disconnected = true
      self.connectedValue = false
    end
    function socket:read(delimiter)
      self.reads = self.reads + 1
      self.readDelimiter = delimiter
    end
    function socket:write(data)
      table.insert(self.writes, data)
    end
    function socket:connectedNow()
      self.connectedValue = true
      self.connectCallback()
    end
    function socket:receive(data)
      self.callback(data)
    end
    table.insert(env.sockets, socket)
    return socket
  end

  hs.timer.doAfter = function(delay, callback)
    local value = timer(delay, callback)
    table.insert(env.afterTimers, value)
    return value
  end
  hs.timer.doEvery = function(delay, callback)
    env.monitor = timer(delay, callback)
    return env.monitor
  end

  function env:runAfter(delay)
    for _, value in ipairs(self.afterTimers) do
      if value.delay == delay and not value.ran and not value.stopped then
        value.ran = true
        value.callback()
        return value
      end
    end
    error("no runnable timer with delay " .. tostring(delay))
  end

  return env
end

local function loadKanata()
  local env = setupHs()
  return env, dofile("kanata.lua")
end

M.tests = {
  {
    name = "connects, tracks profiles, and toggles the Kanata layer",
    run = function()
      local env, kanata = loadKanata()
      local controller = kanata.setup()

      assertEqual(controller.menu.title, "⚠️", "setup should show reconnecting status")
      assertTrue(controller.connectionMonitor ~= nil, "connection monitor should be retained")
      assertTrue(kanata._instances[#kanata._instances] == controller, "module should retain controller")

      env:runAfter(2)
      local socket = env.sockets[1]
      assertEqual(socket.host, "127.0.0.1", "should use the local Kanata host")
      assertEqual(socket.port, 58230, "should use the Kanata socket port")

      socket:connectedNow()
      assertEqual(socket.writes[1], '{"RequestCurrentLayerName":{}}\n', "should request initial layer")
      assertEqual(socket.reads, 1, "should begin reading layer events")

      env.events.base = { CurrentLayerName = { name = "base" } }
      socket:receive("base")
      assertEqual(controller.menu.title, "🐇", "base profile should use the ergonomic icon")
      controller.menu.click()
      assertEqual(socket.writes[2], '{"ChangeLayer":{"new":"normal"}}\n', "click should select normal")

      env.events.normal = { MessagePush = { message = "kanata-profile:normal" } }
      socket:receive("normal")
      assertEqual(controller.menu.title, "🐢", "normal profile should use the normal icon")
      controller.menu.click()
      assertEqual(socket.writes[3], '{"ChangeLayer":{"new":"base"}}\n', "click should select base")
    end,
  },
  {
    name = "reconnects after a connection timeout and stops cleanly",
    run = function()
      local env, kanata = loadKanata()
      local controller = kanata.setup({ reconnectDelay = 3 })

      env:runAfter(3)
      local firstSocket = env.sockets[1]
      env:runAfter(5)
      assertTrue(firstSocket.disconnected, "timed out connection should be disconnected")
      assertEqual(controller.socket, nil, "timed out connection should be cleared")

      env:runAfter(3)
      assertEqual(#env.sockets, 2, "timeout should schedule another connection attempt")
      controller:stop()
      assertTrue(env.monitor.stopped, "stop should stop the connection monitor")
      assertTrue(env.sockets[2].disconnected, "stop should close the active socket")
    end,
  },
}

return M
