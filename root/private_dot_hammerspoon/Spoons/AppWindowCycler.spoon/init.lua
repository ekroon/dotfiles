local obj = {}
obj.__index = obj

obj.name = "AppWindowCycler"
obj.version = "1.11"
obj.author = "Copilot"

local LAUNCH_WAIT_INTERVAL = 0.2
local LAUNCH_TIMEOUT_SECONDS = 10

-- hs.application.find() can return either a single app object or a table of
-- matching app objects when multiple processes share a name. This normalises both.
local function eachFoundApp(appOrApps, callback)
  if not appOrApps then return end
  if type(appOrApps) == "table" and not appOrApps.allWindows then
    for _, app in ipairs(appOrApps) do
      if app and app.allWindows then callback(app) end
    end
  elseif appOrApps.allWindows then
    callback(appOrApps)
  end
end

local function nextCycleIndex(current, total)
  return (current % total) + 1
end

local function windowSetChanged(windows, lastIds)
  if #windows ~= #lastIds then return true end
  for i, item in ipairs(windows) do
    if item.id ~= lastIds[i] then return true end
  end
  return false
end

local function findItemIndexById(items, id)
  if not id then return nil end
  for i, item in ipairs(items) do
    if item.id == id then return i end
  end
  return nil
end

local function findIdIndex(ids, id)
  if not id then return nil end
  for i, cachedId in ipairs(ids) do
    if cachedId == id then return i end
  end
  return nil
end

local function findCurrentItemIndex(items, focusedWindowId)
  if focusedWindowId ~= nil then
    for i, item in ipairs(items) do
      if item.id == focusedWindowId then return i end
    end
  end

  for i, item in ipairs(items) do
    if item.isCurrent and item.isCurrent() then return i end
  end
  return nil
end

local focusWatcherStarted = false
local focusWatcherStartScheduled = false
local focusWatcherAllCyclers = {}
local focusWatcherCyclersByAppName = {}
local focusWatcherAppWatcher = nil

local function focusedWindowForApp(app, eventType)
  local win = app and app:focusedWindow() or nil
  if win ~= nil then return win end

  if eventType == hs.application.watcher.activated then
    return hs.window.focusedWindow()
  end

  return nil
end

local function ensureFocusWatcher()
  if focusWatcherStarted then return end
  focusWatcherStarted = true

  focusWatcherAppWatcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType ~= hs.application.watcher.activated
      and eventType ~= hs.application.watcher.deactivated then return end

    local appCyclers = focusWatcherCyclersByAppName[appName]
    if #focusWatcherAllCyclers == 0 and appCyclers == nil then return end

    local win = focusedWindowForApp(app, eventType)
    if win == nil then return end

    for _, cycler in ipairs(focusWatcherAllCyclers) do
      cycler:rememberFocusedItem(win)
    end

    if appCyclers == nil then return end
    for _, cycler in ipairs(appCyclers) do
      cycler:rememberFocusedItem(win)
    end
  end)
  focusWatcherAppWatcher:start()
end

local function scheduleFocusWatcher()
  if focusWatcherStarted or focusWatcherStartScheduled then return end
  focusWatcherStartScheduled = true
  hs.timer.doAfter(0, ensureFocusWatcher)
end

local function registerFocusWatcherCycler(cycler)
  if cycler.tracksAllFocusedWindows then
    table.insert(focusWatcherAllCyclers, cycler)
    scheduleFocusWatcher()
    return
  end

  for _, appName in ipairs(cycler.appNames) do
    local appCyclers = focusWatcherCyclersByAppName[appName]
    if appCyclers == nil then
      appCyclers = {}
      focusWatcherCyclersByAppName[appName] = appCyclers
    end
    table.insert(appCyclers, cycler)
  end

  scheduleFocusWatcher()
end

-- ── Constructor ───────────────────────────────────────────────────────────────

function obj:new(config)
  local instance = setmetatable({}, self)
  config = config or {}

  instance.appNames         = {}
  instance.appNameSet       = {}
  for i, v in ipairs(config.appNames or {}) do
    instance.appNames[i] = v
    instance.appNameSet[v] = true
  end
  instance.tracksAllFocusedWindows = (#instance.appNames == 0)

  instance.launchAppName    = config.launchAppName or instance.appNames[1]
  instance.launchWhenClosed = (config.launchWhenClosed == true)  -- opt-in; default false
  instance.cycleResetSeconds = config.cycleResetSeconds or 1.5
  instance.includeMinimized = (config.includeMinimized ~= false) -- opt-out; default true

  -- Providers return lists of self-contained items: { id, label, focus [, isCurrent] }.
  -- Multiple providers are concatenated. Defaults to the built-in window provider.
  if config.providers then
    instance.providers = config.providers
  elseif config.itemProvider then
    instance.providers = { config.itemProvider }  -- single-provider shorthand
  else
    instance.providers = {}
  end

  instance._state = { ids = {}, index = 0, itemId = nil, lastCycleAt = nil }
  registerFocusWatcherCycler(instance)

  return instance
end

-- ── Window collection ─────────────────────────────────────────────────────────

-- Returns all standard windows for a single app name, sorted by id.
function obj:windowsForApp(appName)
  local windows = {}
  eachFoundApp(hs.application.find(appName), function(app)
    for _, win in ipairs(app:allWindows() or {}) do
      if win:isStandard() then
        table.insert(windows, { id = win:id(), app = app, win = win })
      end
    end
  end)
  table.sort(windows, function(a, b) return a.id < b.id end)
  return windows
end

-- Returns all standard windows across every configured app, plus a per-app lookup.
-- Windows are ordered by app position in appNames then by window id within each app.
function obj:collectWindows()
  local windows = {}
  local windowsByAppName = {}
  for appOrder, appName in ipairs(self.appNames) do
    local appWindows = self:windowsForApp(appName)
    windowsByAppName[appName] = appWindows

    for _, entry in ipairs(appWindows) do
      table.insert(windows, {
        appOrder = appOrder,
        id       = entry.id,
        app      = entry.app,
        win      = entry.win,
      })
    end
  end
  return windows, windowsByAppName
end

-- Default provider: wraps collected windows into self-contained items.
function obj:defaultWindowItems(windows)
  windows = windows or self:collectWindows()

  local items = {}
  for _, entry in ipairs(windows) do
    local e = entry
    table.insert(items, {
      id        = e.id,
      label     = "",
      focus     = function()
        if self.includeMinimized and e.win:isMinimized() then
          e.win:unminimize()
        end
        e.app:activate(true)
        e.win:focus()
      end,
    })
  end
  return items
end

-- Calls all providers and concatenates their item lists.
-- Falls back to the built-in window provider when no providers are configured.
function obj:collectItems(windows)
  if #self.providers == 0 then
    return self:defaultWindowItems(windows)
  end
  local items = {}
  for _, provider in ipairs(self.providers) do
    for _, v in ipairs(provider()) do
      table.insert(items, v)
    end
  end
  return items
end

function obj:refreshItemState(items)
  if not windowSetChanged(items, self._state.ids) then return end

  self._state.ids = {}
  for i, item in ipairs(items) do self._state.ids[i] = item.id end

  self._state.index = findItemIndexById(items, self._state.itemId)
    or math.min(self._state.index, #items)
end

function obj:rememberFocusedItem(focusedWindow)
  local focusedWindowId = focusedWindow and focusedWindow:id() or nil
  if focusedWindowId == nil then return end

  if #self.providers == 0 then
    self._state.itemId = focusedWindowId
    local cachedIndex = findIdIndex(self._state.ids, focusedWindowId)
    if cachedIndex ~= nil then self._state.index = cachedIndex end
    return
  end

  local items = self:collectItems()
  if #items == 0 then return end

  self:refreshItemState(items)

  local currentIndex = findCurrentItemIndex(items, focusedWindowId)
  if currentIndex == nil then return end

  self._state.index = currentIndex
  self._state.itemId = items[currentIndex].id
end

function obj:tracksFocusedWindow(focusedWindow)
  if focusedWindow == nil then return false end
  if self.tracksAllFocusedWindows then return true end

  local app = focusedWindow:application()
  local appName = app and app:name() or nil
  return self:tracksAppName(appName)
end

function obj:tracksAppName(appName)
  if appName == nil then return false end
  return self.tracksAllFocusedWindows or self.appNameSet[appName] == true
end

function obj:cancelPendingLaunchWait()
  local waitTimer = self._launchWaitTimer
  local timeoutTimer = self._launchTimeoutTimer
  self._launchWaitTimer = nil
  self._launchTimeoutTimer = nil

  if waitTimer ~= nil then waitTimer:stop() end
  if timeoutTimer ~= nil then timeoutTimer:stop() end
end

-- Launches appName and focuses the first window once the app has finished opening.
function obj:launchAndFocus(appName)
  self:cancelPendingLaunchWait()
  self._launchWaitGeneration = (self._launchWaitGeneration or 0) + 1
  local generation = self._launchWaitGeneration
  hs.application.launchOrFocus(appName)

  local wins = {}
  self._launchWaitTimer = hs.timer.waitUntil(
    function()
      wins = self:windowsForApp(appName)
      return #wins > 0
    end,
    function()
      if self._launchWaitGeneration ~= generation then return end
      self:cancelPendingLaunchWait()
      local firstWindow = wins[1]
      if firstWindow == nil then return end
      firstWindow.app:activate(true)
      firstWindow.win:focus()
    end,
    LAUNCH_WAIT_INTERVAL
  )
  self._launchTimeoutTimer = hs.timer.doAfter(LAUNCH_TIMEOUT_SECONDS, function()
    if self._launchWaitGeneration == generation then
      self:cancelPendingLaunchWait()
    end
  end)
end

-- ── Main cycle logic ──────────────────────────────────────────────────────────

function obj:cycle()
  local collectedWindows = nil

  if #self.providers == 0 then
    local windowsByAppName = nil
    collectedWindows, windowsByAppName = self:collectWindows()

    if self.launchWhenClosed then
      for _, appName in ipairs(self.appNames) do
        if #(windowsByAppName[appName] or {}) == 0 then
          self:launchAndFocus(appName)
          return
        end
      end
    end
  elseif self.launchWhenClosed then
    for _, appName in ipairs(self.appNames) do
      if #self:windowsForApp(appName) == 0 then
        self:launchAndFocus(appName)
        return
      end
    end
  end

  local items = self:collectItems(collectedWindows)
  if #items == 0 then return end

  self:refreshItemState(items)

  local focusedWindow = hs.window.focusedWindow()
  local focusedWindowId = focusedWindow and focusedWindow:id() or nil
  local currentIndex = findCurrentItemIndex(items, focusedWindowId)

  local now = hs.timer.secondsSinceEpoch()
  local elapsed = self._state.lastCycleAt ~= nil
    and (now - self._state.lastCycleAt)
    or nil
  local validStateIndex = self._state.index >= 1 and self._state.index <= #items
  local focusMatchesLastTarget = validStateIndex
    and currentIndex == self._state.index
  local focusUnknownDuringCycle = elapsed ~= nil
    and elapsed <= self.cycleResetSeconds
    and validStateIndex
    and currentIndex == nil
    and focusedWindowId == nil

  local idx
  if focusMatchesLastTarget or focusUnknownDuringCycle then
    idx = nextCycleIndex(self._state.index, #items)
  elseif currentIndex ~= nil then
    idx = nextCycleIndex(currentIndex, #items)
  else
    idx = validStateIndex and self._state.index or 1
  end

  self._state.index = idx
  self._state.itemId = items[idx].id
  self._state.lastCycleAt = now
  local item = items[idx]
  item.focus()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function obj:bindHotkey(mods, key)
  hs.hotkey.bind(mods, key, function() self:cycle() end)
end

return obj
