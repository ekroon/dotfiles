local kanata = {
  host = "127.0.0.1",
  port = 58230,
  reconnectDelay = 2,
}

local menu = hs.menubar.new()
local socket
local reconnectTimer
local connectionMonitor
local connectionTimeout
local connecting = false

if not menu then
  error("Unable to create Kanata menu bar item")
end

local function setStatus(status)
  menu:setTitle("⌨ " .. status)
end

local function setProfile(layer)
  if layer == "base" then
    setStatus("Ergonomic")
  elseif layer == "normal" then
    setStatus("Normal")
  end
end

local function scheduleReconnect()
  if connecting or reconnectTimer or (socket and socket:connected()) then
    return
  end

  setStatus("Offline")
  reconnectTimer = hs.timer.doAfter(kanata.reconnectDelay, function()
    reconnectTimer = nil
    socket = nil

    local client
    client = hs.socket.new(function(data)
      local event = hs.json.decode(data)
      if event and event.CurrentLayerName then
        setProfile(event.CurrentLayerName.name)
      elseif event and event.MessagePush then
        if event.MessagePush.message == "kanata-profile:ergonomic" then
          setStatus("Ergonomic")
        elseif event.MessagePush.message == "kanata-profile:normal" then
          setStatus("Normal")
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

menu:setMenu({
  {
    title = "Kanata profile status",
    disabled = true,
  },
})

connectionMonitor = hs.timer.doEvery(kanata.reconnectDelay, function()
  if not socket or not socket:connected() then
    scheduleReconnect()
  end
end)

scheduleReconnect()
