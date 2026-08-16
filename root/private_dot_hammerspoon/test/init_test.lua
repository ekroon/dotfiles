local M = {}

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function loadConfig()
  local previousHs = hs
  local previousSpoon = spoon
  local previousIpc = package.loaded["hs.ipc"]
  local previousFs = package.loaded["hs.fs"]
  local previousKanata = package.loaded.kanata
  local previousApprovedReload = package.loaded.approved_reload
  local approvedOptions = nil
  local approvedController = {}

  package.loaded["hs.ipc"] = {
    cliStatus = function()
      return true
    end,
    cliInstall = function() end,
  }
  package.loaded["hs.fs"] = {
    attributes = function()
      return nil
    end,
  }
  package.loaded.kanata = {
    setup = function() end,
  }
  package.loaded.approved_reload = {
    start = function(options)
      approvedOptions = options
      return approvedController
    end,
  }

  hs = {
    configdir = "/tmp/.hammerspoon",
    loadSpoon = function() end,
  }
  spoon = {
    AppWindowCycler = {},
  }

  function spoon.AppWindowCycler:new(config)
    local cycler = {
      appNames = config.appNames,
      appAliases = config.appAliases,
      launchWhenClosed = config.launchWhenClosed,
    }
    function cycler:bindHotkey(_, key)
      self.key = key
    end
    return cycler
  end

  dofile("init.lua")
  local result = {
    approvedController = hs.approvedReload,
    approvedOptions = approvedOptions,
    cyclers = hs.windowCyclers,
    expectedApprovedController = approvedController,
  }

  hs = previousHs
  spoon = previousSpoon
  package.loaded["hs.ipc"] = previousIpc
  package.loaded["hs.fs"] = previousFs
  package.loaded.kanata = previousKanata
  package.loaded.approved_reload = previousApprovedReload

  return result
end

M.tests = {
  {
    name = "configures approved reloads and application groups",
    run = function()
      local config = loadConfig()
      local cyclers = config.cyclers

      assertEqual(config.approvedOptions.configdir, "/tmp/.hammerspoon", "approved reload config path")
      assertEqual(config.approvedController, config.expectedApprovedController, "approved reload controller")
      assertEqual(table.concat(cyclers.dev.appNames, ","), "GitHub,Code - Insiders,Code,Ghostty", "F2 apps")
      assertEqual(cyclers.dev.appAliases.GitHub, "GitHub Copilot", "F2 GitHub window alias")
      assertEqual(cyclers.dev.launchWhenClosed, false, "F2 launch behavior")
      assertEqual(table.concat(cyclers.terminal.appNames, ","), "Obsidian", "F4 apps")
      assertEqual(cyclers.terminal.launchWhenClosed, true, "F4 launch behavior")
      assertEqual(cyclers.calendar.launchWhenClosed, false, "F5 launch behavior")
    end,
  },
}

return M
