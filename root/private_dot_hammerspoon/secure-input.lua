local M = {
  _instance = nil,
}

local defaults = {
  pollInterval = 0.5,
}

local function deleteMenu(menu)
  if menu then
    menu:delete()
  end
end

function M.setup(config)
  config = config or {}
  local pollInterval = config.pollInterval or defaults.pollInterval
  if type(pollInterval) ~= "number" or pollInterval <= 0 then
    error("Secure Input poll interval must be a positive number")
  end

  if M._instance then
    M._instance:stop()
  end

  local state = {
    menu = nil,
    stopped = false,
    timer = nil,
  }

  local function refresh()
    if state.stopped then
      return
    end

    local ok, enabled = pcall(hs.eventtap.isSecureInputEnabled)
    if not ok or type(enabled) ~= "boolean" then
      return
    end

    if not enabled then
      if state.menu then
        deleteMenu(state.menu)
        state.menu = nil
      end
      return
    end

    if state.menu then
      return
    end

    local menuOk, menu = pcall(hs.menubar.new)
    if not menuOk or not menu then
      return
    end

    local titleOk = pcall(function()
      menu:setTitle("🔒")
    end)
    if not titleOk then
      deleteMenu(menu)
      return
    end
    state.menu = menu
  end

  function state:stop()
    if self.stopped then
      return
    end
    self.stopped = true
    if self.timer then
      self.timer:stop()
    end
    self.timer = nil
    if self.menu then
      deleteMenu(self.menu)
    end
    self.menu = nil
    if M._instance == self then
      M._instance = nil
    end
  end

  state.timer = hs.timer.doEvery(pollInterval, refresh)
  if not state.timer then
    error("Unable to create Secure Input polling timer")
  end

  M._instance = state
  refresh()
  return state
end

return M
