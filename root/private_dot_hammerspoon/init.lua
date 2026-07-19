local ipc = require("hs.ipc")
local fs = require("hs.fs")
local MEH = { "ctrl", "alt", "shift" }

local function ipcCliInstallPrefix()
  if fs.attributes("/opt/homebrew/bin", "mode") == "directory" then
    return "/opt/homebrew"
  end
  return "/usr/local"
end

local ipcCliPrefix = ipcCliInstallPrefix()
if ipc.cliStatus(ipcCliPrefix, true) ~= true then
  ipc.cliInstall(ipcCliPrefix, true)
end

require("kanata").setup()

hs.loadSpoon("AppWindowCycler")
local AppWindowCycler = spoon.AppWindowCycler

local edgeCycler = AppWindowCycler:new({
  appNames = { "Microsoft Edge", "Google Chrome", "Firefox" },
  launchWhenClosed = false,
})
edgeCycler:bindHotkey(MEH, "F1")

local devCycler = AppWindowCycler:new({
  appNames = { "GitHub", "Code - Insiders", "Code" },
  launchWhenClosed = false,
})
devCycler:bindHotkey(MEH, "F2")

local slackCycler = AppWindowCycler:new({
  appNames = { "Slack" },
  launchWhenClosed = true,
})
slackCycler:bindHotkey(MEH, "F3")

local terminalCycler = AppWindowCycler:new({
  appNames = { "Cmux", "Ghostty" },
  launchWhenClosed = false,
})
terminalCycler:bindHotkey(MEH, "F4")

local calendarCycler = AppWindowCycler:new({
  appNames = { "Microsoft Teams", "Microsoft Outlook", "Reclaim" },
  launchWhenClosed = true,
})
calendarCycler:bindHotkey(MEH, "F5")

hs.windowCyclers = {
  edge = edgeCycler,
  dev = devCycler,
  slack = slackCycler,
  terminal = terminalCycler,
  calendar = calendarCycler,
}

function hs.cycleWindowGroup(name)
  local cycler = hs.windowCyclers[name]
  if not cycler then
    return false, "Unknown window group: " .. tostring(name)
  end

  cycler:cycle()
  return true, "Cycled window group: " .. name
end
