local M = {
  _instances = {},
}

local defaults = {
  host = "127.0.0.1",
  port = 58230,
  reconnectDelay = 2,
}

local function stopTimer(timer)
  if timer then timer:stop() end
end

function M.setup(config)
  config = config or {}
  local kanata = {
    host = config.host or defaults.host,
    port = config.port or defaults.port,
    reconnectDelay = config.reconnectDelay or defaults.reconnectDelay,
  }
  local state = {
    activeProfile = nil,
    connecting = false,
    connectionMonitor = nil,
    connectionTimeout = nil,
    menu = hs.menubar.new(),
    reconnectTimer = nil,
    socket = nil,
    stopped = false,
  }

  if not state.menu then
    error("Unable to create Kanata menu bar item")
  end

  local function setStatus(icon)
    state.menu:setTitle(icon)
  end

  local function setProfile(layer)
    if layer == "base" then
      state.activeProfile = layer
      setStatus("🐇")
    elseif layer == "normal" then
      state.activeProfile = layer
      setStatus("🐢")
    end
  end

  local scheduleReconnect

  local function stopConnectionTimeout()
    stopTimer(state.connectionTimeout)
    state.connectionTimeout = nil
  end

  local function requestCurrentLayer(client)
    if state.socket ~= client or state.stopped then return end
    state.connecting = false
    stopConnectionTimeout()
    client:write('{"RequestCurrentLayerName":{}}\n')
    client:read("\n")
  end

  scheduleReconnect = function()
    if state.stopped or state.connecting or state.reconnectTimer
      or (state.socket and state.socket:connected()) then
      return
    end

    setStatus("⚠️")
    state.reconnectTimer = hs.timer.doAfter(kanata.reconnectDelay, function()
      state.reconnectTimer = nil
      if state.stopped or (state.socket and state.socket:connected()) then return end

      state.socket = nil
      local client
      client = hs.socket.new(function(data)
        local ok, event = pcall(hs.json.decode, data)
        if ok and event and event.CurrentLayerName then
          setProfile(event.CurrentLayerName.name)
        elseif ok and event and event.LayerChange then
          setProfile(event.LayerChange.new)
        elseif ok and event and event.MessagePush then
          if event.MessagePush.message == "kanata-profile:ergonomic" then
            setProfile("base")
          elseif event.MessagePush.message == "kanata-profile:normal" then
            setProfile("normal")
          end
        end

        if state.socket == client and not state.stopped then
          client:read("\n")
        end
      end)

      state.connecting = true
      state.socket = client
      state.connectionTimeout = hs.timer.doAfter(5, function()
        if state.connecting and state.socket == client then
          state.connecting = false
          state.socket = nil
          client:disconnect()
          scheduleReconnect()
        end
      end)

      if not client:connect(kanata.host, kanata.port, function()
        requestCurrentLayer(client)
      end) then
        if state.socket == client then
          state.connecting = false
          stopConnectionTimeout()
          state.socket = nil
          scheduleReconnect()
        end
      end
    end)
  end

  local function toggleProfile()
    if not state.socket or not state.socket:connected() then
      scheduleReconnect()
      return
    end

    if state.activeProfile == "base" then
      state.socket:write('{"ChangeLayer":{"new":"normal"}}\n')
    elseif state.activeProfile == "normal" then
      state.socket:write('{"ChangeLayer":{"new":"base"}}\n')
    else
      state.socket:write('{"RequestCurrentLayerName":{}}\n')
    end
  end

  function state:stop()
    if self.stopped then return end
    self.stopped = true
    stopTimer(self.reconnectTimer)
    stopTimer(self.connectionTimeout)
    stopTimer(self.connectionMonitor)
    self.reconnectTimer = nil
    self.connectionTimeout = nil
    self.connectionMonitor = nil
    if self.socket then self.socket:disconnect() end
    self.socket = nil
  end

  state.menu:setClickCallback(toggleProfile)
  state.connectionMonitor = hs.timer.doEvery(kanata.reconnectDelay, function()
    if not state.socket or not state.socket:connected() then
      scheduleReconnect()
    end
  end)
  scheduleReconnect()

  table.insert(M._instances, state)
  return state
end

return M
