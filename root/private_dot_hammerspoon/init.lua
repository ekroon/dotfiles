local kanata = {
  host = "127.0.0.1",
  port = 58230,
  reconnectDelay = 2,
}

local menu = hs.menubar.new()
local socket
local reconnectTimer
local scheduleReconnect
local connectionMonitor
local connectionTimeout
local connecting = false
local activeProfile

if not menu then
  error("Unable to create Kanata menu bar item")
end

local function setStatus(icon)
  menu:setTitle(icon)
end

local function setProfile(layer)
  if layer == "base" then
    activeProfile = layer
    setStatus("🐇")
  elseif layer == "normal" then
    activeProfile = layer
    setStatus("🐢")
  end
end

local function toggleProfile()
  if not socket or not socket:connected() then
    scheduleReconnect()
    return
  end

  if activeProfile == "base" then
    socket:write('{"ChangeLayer":{"new":"normal"}}\n')
  elseif activeProfile == "normal" then
    socket:write('{"ChangeLayer":{"new":"base"}}\n')
  else
    socket:write('{"RequestCurrentLayerName":{}}\n')
  end
end

scheduleReconnect = function()
  if connecting or reconnectTimer or (socket and socket:connected()) then
    return
  end

  setStatus("⚠️")
  reconnectTimer = hs.timer.doAfter(kanata.reconnectDelay, function()
    reconnectTimer = nil
    socket = nil

    local client
    client = hs.socket.new(function(data)
      local event = hs.json.decode(data)
      if event and event.CurrentLayerName then
        setProfile(event.CurrentLayerName.name)
      elseif event and event.LayerChange then
        setProfile(event.LayerChange.new)
      elseif event and event.MessagePush then
        if event.MessagePush.message == "kanata-profile:ergonomic" then
          setProfile("base")
        elseif event.MessagePush.message == "kanata-profile:normal" then
          setProfile("normal")
        end
      end

      client:read("\n")
    end)

    connecting = true
    socket = client
    connectionTimeout = hs.timer.doAfter(5, function()
      if connecting then
        connecting = false
        socket = nil
        client:disconnect()
        scheduleReconnect()
      end
    end)

    if not client:connect(kanata.host, kanata.port, function()
      connecting = false
      connectionTimeout:stop()
      connectionTimeout = nil
      client:write('{"RequestCurrentLayerName":{}}\n')
      client:read("\n")
    end) then
      connecting = false
      connectionTimeout:stop()
      connectionTimeout = nil
      socket = nil
      scheduleReconnect()
    end
  end)
end

menu:setClickCallback(toggleProfile)

connectionMonitor = hs.timer.doEvery(kanata.reconnectDelay, function()
  if not socket or not socket:connected() then
    scheduleReconnect()
  end
end)

scheduleReconnect()
