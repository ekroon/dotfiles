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

local function setupHs(initialSecureInput)
  local env = {
    failMenuCreation = false,
    failSecureInputRead = false,
    menus = {},
    secureInput = initialSecureInput,
    timers = {},
  }

  hs = {
    eventtap = {},
    menubar = {},
    timer = {},
  }

  hs.eventtap.isSecureInputEnabled = function()
    if env.failSecureInputRead then
      error("secure input unavailable")
    end
    return env.secureInput
  end

  hs.menubar.new = function()
    env.menuCreationCount = (env.menuCreationCount or 0) + 1
    if env.failMenuCreation then
      return nil
    end

    local menu = {
      clickCallbackCalls = 0,
      deleteCalls = 0,
      setTitleCalls = 0,
    }
    function menu:setClickCallback(callback)
      self.clickCallback = callback
      self.clickCallbackCalls = self.clickCallbackCalls + 1
    end
    function menu:setTitle(title)
      self.title = title
      self.setTitleCalls = self.setTitleCalls + 1
    end
    function menu:delete()
      self.deleteCalls = self.deleteCalls + 1
    end
    table.insert(env.menus, menu)
    return menu
  end

  hs.timer.doEvery = function(interval, callback)
    local timer = {
      callback = callback,
      interval = interval,
      stopCalls = 0,
    }
    function timer:stop()
      self.stopCalls = self.stopCalls + 1
    end
    table.insert(env.timers, timer)
    return timer
  end

  function env:tick(timerIndex)
    self.timers[timerIndex or #self.timers].callback()
  end

  return env
end

local function loadSecureInput(initialSecureInput)
  local env = setupHs(initialSecureInput)
  return env, dofile("secure-input.lua")
end

M.tests = {
  {
    name = "starts hidden and polls at the default interval",
    run = function()
      local env, secureInput = loadSecureInput(false)
      local controller = secureInput.setup()

      assertEqual(#env.timers, 1, "setup should retain one polling timer")
      assertEqual(env.timers[1].interval, 0.5, "default polling interval")
      assertEqual(env.menuCreationCount or 0, 0, "disabled state should not create a menu item")
      assertEqual(controller.menu, nil, "disabled state should remain hidden")
    end,
  },
  {
    name = "shows one passive lock item while Secure Input is enabled",
    run = function()
      local env, secureInput = loadSecureInput(true)
      local controller = secureInput.setup()
      local menu = env.menus[1]

      assertEqual(#env.menus, 1, "enabled state should create one menu item")
      assertEqual(menu.title, "🔒", "enabled title")
      assertEqual(menu.setTitleCalls, 1, "title should be assigned once")
      assertEqual(menu.clickCallbackCalls, 0, "indicator should not have click behavior")
      assertTrue(controller.menu == menu, "controller should retain the visible menu item")

      env:tick()
      assertEqual(#env.menus, 1, "unchanged enabled polls should reuse the menu item")
      assertEqual(menu.setTitleCalls, 1, "unchanged enabled polls should not retitle")
    end,
  },
  {
    name = "updates only on Secure Input transitions",
    run = function()
      local env, secureInput = loadSecureInput(false)
      local controller = secureInput.setup({ pollInterval = 1 })

      assertEqual(env.timers[1].interval, 1, "custom polling interval")
      env.secureInput = true
      env:tick()
      local menu = env.menus[1]
      assertEqual(menu.title, "🔒", "false-to-true should show the lock")
      assertTrue(controller.menu == menu, "controller should retain the lock item")

      env:tick()
      assertEqual(menu.setTitleCalls, 1, "repeated true should not mutate the title")

      env.secureInput = false
      env:tick()
      assertEqual(menu.deleteCalls, 1, "true-to-false should delete the lock")
      assertEqual(controller.menu, nil, "controller should clear the deleted item")

      env:tick()
      assertEqual(menu.deleteCalls, 1, "repeated false should not delete again")
    end,
  },
  {
    name = "preserves presentation when the Secure Input query fails",
    run = function()
      local env, secureInput = loadSecureInput(true)
      local controller = secureInput.setup()
      local menu = env.menus[1]

      env.failSecureInputRead = true
      env.secureInput = false
      env:tick()
      assertTrue(controller.menu == menu, "failed reads should preserve the visible item")
      assertEqual(menu.deleteCalls, 0, "failed reads should not delete the item")

      env.failSecureInputRead = false
      env:tick()
      assertEqual(menu.deleteCalls, 1, "the next successful false read should delete the item")
    end,
  },
  {
    name = "retries a failed menu allocation",
    run = function()
      local env, secureInput = loadSecureInput(true)
      env.failMenuCreation = true
      local controller = secureInput.setup()

      assertEqual(env.menuCreationCount, 1, "initial enabled refresh should try to create the item")
      assertEqual(controller.menu, nil, "failed allocation should not retain a menu")

      env.failMenuCreation = false
      env:tick()
      assertEqual(env.menuCreationCount, 2, "enabled polling should retry allocation")
      assertEqual(env.menus[1].title, "🔒", "retry should create the lock item")
    end,
  },
  {
    name = "stops cleanly and replaces an existing instance",
    run = function()
      local env, secureInput = loadSecureInput(true)
      local first = secureInput.setup()
      local firstTimer = env.timers[1]
      local firstMenu = env.menus[1]

      local second = secureInput.setup()
      assertEqual(firstTimer.stopCalls, 1, "replacement should stop the previous timer")
      assertEqual(firstMenu.deleteCalls, 1, "replacement should delete the previous item")
      assertTrue(secureInput._instance == second, "module should retain the replacement")

      local secondTimer = env.timers[2]
      local secondMenu = env.menus[2]
      second:stop()
      second:stop()
      assertEqual(secondTimer.stopCalls, 1, "stop should be idempotent for the timer")
      assertEqual(secondMenu.deleteCalls, 1, "stop should be idempotent for the item")
      assertEqual(secureInput._instance, nil, "stop should clear the retained instance")
    end,
  },
}

return M
