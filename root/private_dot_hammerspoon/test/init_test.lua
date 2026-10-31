local M = {}

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        "%s: expected %s, got %s",
        message or "values should be equal",
        tostring(expected),
        tostring(actual)
      ),
      2
    )
  end
end

local function assertTrue(value, message)
  if not value then
    error(message or "expected value to be truthy", 2)
  end
end

local function loadConfig()
  local previousHs = hs
  local previousSpoon = spoon
  local previousIpc = package.loaded["hs.ipc"]
  local previousFs = package.loaded["hs.fs"]
  local previousKanata = package.loaded.kanata
  local previousApprovedReload = package.loaded.approved_reload
  local previousSecureInput = package.loaded["secure-input"]
  local approvedOptions = nil
  local approvedController = {}
  local secureInputController = {
    stopCalls = 0,
  }
  function secureInputController:stop()
    self.stopCalls = self.stopCalls + 1
  end
  local secureInputSetupCalls = 0
  local previousShutdownCalls = 0

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
  package.loaded["secure-input"] = {
    setup = function()
      secureInputSetupCalls = secureInputSetupCalls + 1
      return secureInputController
    end,
  }

  hs = {
    configdir = "/tmp/.hammerspoon",
    loadSpoon = function() end,
    shutdownCallback = function()
      previousShutdownCalls = previousShutdownCalls + 1
    end,
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
  local config = {
    approvedController = hs.approvedReload,
    approvedOptions = approvedOptions,
    cyclers = hs.windowCyclers,
    expectedApprovedController = approvedController,
    previousShutdownCalls = function()
      return previousShutdownCalls
    end,
    secureInputController = secureInputController,
    secureInputIndicator = hs.secureInputIndicator,
    secureInputSetupCalls = secureInputSetupCalls,
    shutdownCallback = hs.shutdownCallback,
  }

  hs = previousHs
  spoon = previousSpoon
  package.loaded["hs.ipc"] = previousIpc
  package.loaded["hs.fs"] = previousFs
  package.loaded.kanata = previousKanata
  package.loaded.approved_reload = previousApprovedReload
  package.loaded["secure-input"] = previousSecureInput

  return config
end

M.tests = {
  {
    name = "configures approved reloads and application groups",
    run = function()
      local config = loadConfig()
      local cyclers = config.cyclers

      assertEqual(config.approvedOptions.configdir, "/tmp/.hammerspoon", "approved reload config path")
      assertEqual(config.approvedController, config.expectedApprovedController, "approved reload controller")
      assertEqual(table.concat(cyclers.dev.appNames, ","), "GitHub,Codex,Code - Insiders,Code,Ghostty", "F2 apps")
      assertEqual(cyclers.dev.appAliases.GitHub, "GitHub Copilot", "F2 GitHub window alias")
      assertEqual(cyclers.dev.launchWhenClosed, false, "F2 launch behavior")
      assertEqual(table.concat(cyclers.terminal.appNames, ","), "Obsidian", "F4 apps")
      assertEqual(cyclers.terminal.launchWhenClosed, true, "F4 launch behavior")
      assertEqual(cyclers.calendar.launchWhenClosed, false, "F5 launch behavior")
    end,
  },
  {
    name = "configures and shuts down the Secure Input indicator",
    run = function()
      local config = loadConfig()

      assertEqual(config.secureInputSetupCalls, 1, "Secure Input setup calls")
      assertTrue(
        config.secureInputIndicator == config.secureInputController,
        "Secure Input controller should be retained on hs"
      )

      config.shutdownCallback()
      assertEqual(config.secureInputController.stopCalls, 1, "shutdown should stop the Secure Input controller")
      assertEqual(config.previousShutdownCalls(), 1, "shutdown should invoke the previous callback")
    end,
  },
}

return M
