local M = {}

local MODULE_PATH = "approved_reload.lua"
local HEADER_INVENTORY = "approved-reload-inventory-v1\n"
local HEADER_MANIFEST = "approved-reload-manifest-v1\n"
local HEADER_APPROVAL = "approved-reload-approval-v1\n"
local FILES = {
  "Spoons/AppWindowCycler.spoon/init.lua",
  "approved_reload.lua",
  "init.lua",
  "kanata.lua",
}

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertError(callback, message)
  local ok = pcall(callback)
  if ok then
    error(message or "expected an error", 2)
  end
end

local function inventory()
  return HEADER_INVENTORY .. table.concat(FILES, "\n") .. "\n"
end

local function manifest(hashes)
  local lines = { HEADER_MANIFEST:sub(1, -2) }
  for _, path in ipairs(FILES) do
    table.insert(lines, hashes[path] .. "\t" .. path)
  end
  return table.concat(lines, "\n") .. "\n"
end

local function loadModule()
  return dofile(MODULE_PATH)
end

local function fakeEnvironment()
  local hashes = {
    ["Spoons/AppWindowCycler.spoon/init.lua"] = string.rep("a", 64),
    ["approved_reload.lua"] = string.rep("b", 64),
    ["init.lua"] = string.rep("c", 64),
    ["kanata.lua"] = string.rep("d", 64),
  }
  local manifestBytes = manifest(hashes)
  local files = {
    ["reload-inventory"] = inventory(),
    ["reload-manifest"] = manifestBytes,
    ["reload-approval"] = HEADER_APPROVAL .. string.rep("e", 64) .. "\n",
  }
  local timers = {}
  local reloadCount = 0
  local watcherCallback = nil

  local deps = {
    readFile = function(path)
      return files[path]
    end,
    hashBytes = function(bytes)
      if bytes == manifestBytes then
        return string.rep("e", 64)
      end
      if bytes == files["reload-inventory"] then
        return string.rep("9", 64)
      end
      error("unexpected bytes")
    end,
    hashFile = function(path)
      return hashes[path]
    end,
    discoverLuaFiles = function()
      local discovered = {}
      for i, path in ipairs(FILES) do
        discovered[i] = path
      end
      return discovered
    end,
    newWatcher = function(_, callback)
      watcherCallback = callback
      return {
        start = function(self)
          self.started = true
          return self
        end,
      }
    end,
    doAfter = function(delay, callback)
      local timer = { delay = delay, callback = callback, stopped = false }
      function timer:stop()
        self.stopped = true
      end
      table.insert(timers, timer)
      return timer
    end,
    reload = function()
      reloadCount = reloadCount + 1
    end,
  }

  return {
    deps = deps,
    files = files,
    hashes = hashes,
    manifestBytes = function()
      return manifestBytes
    end,
    reloadCount = function()
      return reloadCount
    end,
    runTimer = function(delay)
      for _, timer in ipairs(timers) do
        if timer.delay == delay and not timer.stopped and not timer.ran then
          timer.ran = true
          timer.callback()
          return
        end
      end
      error("no runnable timer with delay " .. tostring(delay))
    end,
    setManifest = function(value)
      manifestBytes = value
      files["reload-manifest"] = value
    end,
    watcherCallback = function(paths)
      watcherCallback(paths)
    end,
  }
end

M.tests = {
  {
    name = "parses canonical reload artifacts",
    run = function()
      local approvedReload = loadModule()
      local hashes = {
        ["Spoons/AppWindowCycler.spoon/init.lua"] = string.rep("a", 64),
        ["approved_reload.lua"] = string.rep("b", 64),
        ["init.lua"] = string.rep("c", 64),
        ["kanata.lua"] = string.rep("d", 64),
      }

      local parsedInventory = approvedReload.parseInventory(inventory())
      assertEqual(table.concat(parsedInventory, ","), table.concat(FILES, ","), "inventory paths")

      local parsedManifest = approvedReload.parseManifest(manifest(hashes), parsedInventory)
      assertEqual(parsedManifest["init.lua"], hashes["init.lua"], "manifest hash")

      local approval = approvedReload.parseApproval(HEADER_APPROVAL .. string.rep("e", 64) .. "\n")
      assertEqual(approval, string.rep("e", 64), "approval digest")
    end,
  },
  {
    name = "rejects unsafe or noncanonical reload artifacts",
    run = function()
      local approvedReload = loadModule()

      assertError(function()
        approvedReload.parseInventory(HEADER_INVENTORY .. "../init.lua\n")
      end, "parent traversal should fail")
      assertError(function()
        approvedReload.parseInventory(HEADER_INVENTORY .. "init.lua\napproved_reload.lua\n")
      end, "unsorted inventory should fail")
      assertError(function()
        approvedReload.parseInventory(inventory():sub(1, -2))
      end, "missing final newline should fail")
      assertError(function()
        approvedReload.parseManifest(HEADER_MANIFEST .. string.rep("a", 64) .. "\tinit.lua\n", FILES)
      end, "incomplete manifest should fail")
      assertError(function()
        approvedReload.parseApproval(HEADER_APPROVAL .. string.rep("A", 64) .. "\n")
      end, "uppercase digest should fail")
    end,
  },
  {
    name = "verifies the complete approval chain",
    run = function()
      local approvedReload = loadModule()
      local env = fakeEnvironment()
      local controller = approvedReload.new({ configdir = "", deps = env.deps })

      local snapshot = controller:verify()
      assertEqual(snapshot.identity, string.rep("e", 64), "approved identity")
      assertEqual(#snapshot.files, #FILES, "snapshot file count")

      env.files["reload-approval"] = HEADER_APPROVAL .. string.rep("f", 64) .. "\n"
      assertEqual(controller:verify(), nil, "wrong approval pin should be inert")

      env.files["reload-approval"] = HEADER_APPROVAL .. string.rep("e", 64) .. "\n"
      env.deps.discoverLuaFiles = function()
        return { table.unpack(FILES), "unexpected.lua" }
      end
      assertEqual(controller:verify(), nil, "unknown runtime files should be inert")
    end,
  },
  {
    name = "reloads exactly once after stable approved changes",
    run = function()
      local approvedReload = loadModule()
      local env = fakeEnvironment()
      local controller = approvedReload.new({ configdir = "", deps = env.deps }):start()

      env.watcherCallback({ "init.lua" })
      env.runTimer(0.5)
      assertEqual(env.reloadCount(), 0, "unchanged approval should not reload")

      local nextHashes = {}
      for path, hash in pairs(env.hashes) do
        nextHashes[path] = hash
      end
      nextHashes["init.lua"] = string.rep("1", 64)
      env.hashes["init.lua"] = nextHashes["init.lua"]
      local nextManifest = manifest(nextHashes)
      env.setManifest(nextManifest)
      env.files["reload-approval"] = HEADER_APPROVAL .. string.rep("f", 64) .. "\n"
      env.deps.hashBytes = function(bytes)
        if bytes == nextManifest then
          return string.rep("f", 64)
        end
        if bytes == env.files["reload-inventory"] then
          return string.rep("9", 64)
        end
        return string.rep("e", 64)
      end

      env.watcherCallback({ "reload-approval" })
      env.runTimer(0.5)
      env.runTimer(0.25)
      assertEqual(env.reloadCount(), 1, "stable approved change should reload")
    end,
  },
  {
    name = "does not reload when the second verification changes",
    run = function()
      local approvedReload = loadModule()
      local env = fakeEnvironment()
      approvedReload.new({ configdir = "", deps = env.deps }):start()

      local nextHashes = {}
      for path, hash in pairs(env.hashes) do
        nextHashes[path] = hash
      end
      nextHashes["init.lua"] = string.rep("1", 64)
      env.hashes["init.lua"] = nextHashes["init.lua"]
      local nextManifest = manifest(nextHashes)
      env.setManifest(nextManifest)
      env.files["reload-approval"] = HEADER_APPROVAL .. string.rep("f", 64) .. "\n"
      env.deps.hashBytes = function(bytes)
        if bytes == env.files["reload-inventory"] then
          return string.rep("9", 64)
        end
        return string.rep("f", 64)
      end

      env.watcherCallback({ "reload-manifest" })
      env.runTimer(0.5)
      env.hashes["kanata.lua"] = string.rep("2", 64)
      env.runTimer(0.25)
      assertEqual(env.reloadCount(), 0, "unstable configuration should not reload")
    end,
  },
  {
    name = "cancels verification when another filesystem event arrives",
    run = function()
      local approvedReload = loadModule()
      local env = fakeEnvironment()
      approvedReload.new({ configdir = "", deps = env.deps }):start()

      local nextHashes = {}
      for path, hash in pairs(env.hashes) do
        nextHashes[path] = hash
      end
      nextHashes["init.lua"] = string.rep("1", 64)
      env.hashes["init.lua"] = nextHashes["init.lua"]
      local nextManifest = manifest(nextHashes)
      env.setManifest(nextManifest)
      env.files["reload-approval"] = HEADER_APPROVAL .. string.rep("f", 64) .. "\n"
      env.deps.hashBytes = function(bytes)
        if bytes == env.files["reload-inventory"] then
          return string.rep("9", 64)
        end
        return string.rep("f", 64)
      end

      env.watcherCallback({ "reload-approval" })
      env.runTimer(0.5)
      env.watcherCallback({ "init.lua" })
      assertError(function()
        env.runTimer(0.25)
      end, "the stale second verification timer should be cancelled")
      assertEqual(env.reloadCount(), 0, "a new event should cancel the pending reload")
    end,
  },
}

return M
