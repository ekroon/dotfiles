local M = {}

local SPOON_PATH = "Spoons/AppWindowCycler.spoon/init.lua"

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
  if not value then
    error(message or "expected value to be truthy", 2)
  end
end

local function setupHs()
  local env = {
    appsByName = {},
    findCounts = {},
    focusedWindow = nil,
    focusedId = nil,
    launchedAppName = nil,
    activatedAppName = nil,
    onLaunch = nil,
    watcherCallback = nil,
    watcherStarted = false,
    afterTimers = {},
    waitTimers = {},
    waitInterval = nil,
    waitPredicateCalls = 0,
    now = 0,
    minimized = {},
    unminimized = {},
  }

  hs = {
    application = {},
    window = {},
    timer = {},
    hotkey = {},
  }

  hs.application.watcher = {
    activated = 1,
    deactivated = 2,
    new = function(callback)
      env.watcherCallback = callback
      return {
        start = function()
          env.watcherStarted = true
        end,
      }
    end,
  }

  hs.application.find = function(name)
    env.findCounts[name] = (env.findCounts[name] or 0) + 1
    return env.appsByName[name]
  end

  hs.application.launchOrFocus = function(name)
    env.launchedAppName = name
    if env.onLaunch then env.onLaunch(name) end
  end

  hs.window.focusedWindow = function()
    return env.focusedWindow
  end

  hs.timer.doAfter = function(delay, callback)
    local value = {
      callback = callback,
      delay = delay,
      stopped = false,
    }
    function value:stop()
      self.stopped = true
    end
    table.insert(env.afterTimers, value)
    if delay == 0 then
      value.ran = true
      callback()
    end
    return value
  end

  hs.timer.secondsSinceEpoch = function()
    env.now = env.now + 0.1
    return env.now
  end

  hs.timer.waitUntil = function(predicate, callback, interval)
    env.waitInterval = interval
    local value = {
      callback = callback,
      interval = interval,
      predicate = predicate,
      stopped = false,
    }
    function value:stop()
      self.stopped = true
    end
    table.insert(env.waitTimers, value)
    return value
  end

  hs.hotkey.bind = function() end

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

  function env:runWait(interval)
    for _, value in ipairs(self.waitTimers) do
      if value.interval == interval and not value.stopped then
        self.waitPredicateCalls = self.waitPredicateCalls + 1
        if value.predicate() then
          value.stopped = true
          value.callback()
        end
        return value
      end
    end
    error("no runnable wait timer with interval " .. tostring(interval))
  end

  return env
end

local function makeWindow(env, id, opts)
  opts = opts or {}

  local win = {}

  function win:id()
    return id
  end

  function win:isStandard()
    return opts.standard ~= false
  end

  function win:isMinimized()
    return env.minimized[id] == true
  end

  function win:unminimize()
    env.unminimized[id] = true
    env.minimized[id] = false
  end

  function win:focus()
    env.focusedId = id
    env.focusedWindow = win
  end

  function win:title()
    return opts.title or ("window " .. tostring(id))
  end

  function win:application()
    return win._app
  end

  return win
end

local function makeApp(env, name, windows)
  local app = {}

  function app:name()
    return name
  end

  function app:allWindows()
    return windows
  end

  function app:focusedWindow()
    if env.focusedWindow and env.focusedWindow:application() == app then
      return env.focusedWindow
    end
    return windows[1]
  end

  function app:activate(force)
    env.activatedAppName = name
    env.activateForce = force
  end

  for _, win in ipairs(windows) do
    win._app = app
  end

  return app
end

local function setApp(env, name, windows)
  env.appsByName[name] = makeApp(env, name, windows)
  return env.appsByName[name]
end

local function loadCycler()
  local env = setupHs()
  return env, dofile(SPOON_PATH)
end

M.tests = {
  {
    name = "cycles default windows with one collection per app",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winA = makeWindow(env, 101)
      local winB = makeWindow(env, 202)
      setApp(env, "A", { winA })
      setApp(env, "B", { winB })

      local cycler = AppWindowCycler:new({ appNames = { "A", "B" } })
      cycler:cycle()

      assertEqual(env.focusedId, 101, "first cycle should focus the first app window")
      assertEqual(env.findCounts.A, 1, "A should be enumerated once on first cycle")
      assertEqual(env.findCounts.B, 1, "B should be enumerated once on first cycle")

      env.focusedWindow = winA
      cycler:cycle()

      assertEqual(env.focusedId, 202, "second cycle should advance from focused window")
      assertEqual(env.findCounts.A, 2, "A should be enumerated once per cycle")
      assertEqual(env.findCounts.B, 2, "B should be enumerated once per cycle")
    end,
  },
  {
    name = "launches and focuses first app without windows",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winA = makeWindow(env, 101)
      local winB = makeWindow(env, 202)
      setApp(env, "A", { winA })
      setApp(env, "B", {})
      env.onLaunch = function(name)
        if name == "B" then setApp(env, "B", { winB }) end
      end

      local cycler = AppWindowCycler:new({
        appNames = { "A", "B" },
        launchWhenClosed = true,
      })
      cycler:cycle()
      env:runWait(0.2)

      assertEqual(env.launchedAppName, "B", "missing app should be launched")
      assertEqual(env.focusedId, 202, "newly launched app window should be focused")
      assertEqual(env.findCounts.A, 1, "present app should be enumerated once")
      assertEqual(env.findCounts.B, 2, "missing app should be collected once and polled once")
      assertEqual(env.waitInterval, 0.2, "launch wait interval should be preserved")
    end,
  },
  {
    name = "stops and clears launch waits that exceed the timeout",
    run = function()
      local env, AppWindowCycler = loadCycler()
      setApp(env, "B", {})
      local cycler = AppWindowCycler:new({ appNames = { "B" } })

      cycler:launchAndFocus("B")
      local waitTimer = cycler._launchWaitTimer
      local timeoutTimer = cycler._launchTimeoutTimer
      assertTrue(waitTimer ~= nil, "launch wait should be retained")
      assertTrue(timeoutTimer ~= nil, "launch timeout should be retained")

      env:runWait(0.2)
      env:runAfter(10)

      assertTrue(waitTimer.stopped, "timed out launch wait should stop")
      assertEqual(cycler._launchWaitTimer, nil, "timed out launch wait should clear")
      assertEqual(cycler._launchTimeoutTimer, nil, "timed out launch timeout should clear")
    end,
  },
  {
    name = "replaces pending launch waits on repeated cycles",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winB = makeWindow(env, 202)
      setApp(env, "B", {})
      local cycler = AppWindowCycler:new({
        appNames = { "B" },
        launchWhenClosed = true,
      })

      cycler:cycle()
      local firstWaitTimer = cycler._launchWaitTimer
      local firstTimeoutTimer = cycler._launchTimeoutTimer
      cycler:cycle()
      local secondWaitTimer = cycler._launchWaitTimer
      local secondTimeoutTimer = cycler._launchTimeoutTimer

      assertTrue(firstWaitTimer.stopped, "retry should stop the prior launch wait")
      assertTrue(firstTimeoutTimer.stopped, "retry should stop the prior launch timeout")
      assertTrue(secondWaitTimer ~= firstWaitTimer, "retry should create a new launch wait")

      setApp(env, "B", { winB })
      env:runWait(0.2)

      assertEqual(env.focusedId, 202, "retry should focus the launched window")
      assertTrue(secondWaitTimer.stopped, "successful launch wait should stop")
      assertTrue(secondTimeoutTimer.stopped, "successful launch timeout should stop")
      assertEqual(cycler._launchWaitTimer, nil, "successful launch wait should clear")
      assertEqual(cycler._launchTimeoutTimer, nil, "successful launch timeout should clear")
    end,
  },
  {
    name = "focus watcher updates only matching app cyclers",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winA = makeWindow(env, 101)
      local winB = makeWindow(env, 202)
      local appA = setApp(env, "A", { winA })
      setApp(env, "B", { winB })

      local cyclerA = AppWindowCycler:new({ appNames = { "A" } })
      local cyclerB = AppWindowCycler:new({ appNames = { "B" } })

      assertTrue(env.watcherStarted, "focus watcher should start")
      env.watcherCallback("A", hs.application.watcher.activated, appA)

      assertEqual(cyclerA._state.itemId, 101, "matching cycler should remember focus")
      assertEqual(cyclerB._state.itemId, nil, "non-matching cycler should not update")
    end,
  },
  {
    name = "focus watcher supports track-all cyclers",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winA = makeWindow(env, 101)
      local appA = setApp(env, "A", { winA })

      local cycler = AppWindowCycler:new({})
      env.watcherCallback("A", hs.application.watcher.activated, appA)

      assertEqual(cycler._state.itemId, 101, "track-all cycler should remember any app focus")
    end,
  },
  {
    name = "custom providers use isCurrent fallback",
    run = function()
      local _, AppWindowCycler = loadCycler()
      local focusedItem = nil
      local cycler = AppWindowCycler:new({
        providers = {
          function()
            return {
              { id = "one", focus = function() focusedItem = "one" end },
              {
                id = "two",
                focus = function() focusedItem = "two" end,
                isCurrent = function() return true end,
              },
              { id = "three", focus = function() focusedItem = "three" end },
            }
          end,
        },
      })

      cycler:cycle()

      assertEqual(focusedItem, "three", "cycler should advance from provider current item")
    end,
  },
  {
    name = "unminimizes minimized windows before focusing",
    run = function()
      local env, AppWindowCycler = loadCycler()
      local winA = makeWindow(env, 101)
      env.minimized[101] = true
      setApp(env, "A", { winA })

      local cycler = AppWindowCycler:new({ appNames = { "A" } })
      cycler:cycle()

      assertTrue(env.unminimized[101], "minimized window should be unminimized")
      assertEqual(env.focusedId, 101, "unminimized window should be focused")
    end,
  },
}

return M
