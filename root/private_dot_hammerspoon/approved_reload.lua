local M = {}

local INVENTORY_HEADER = "approved-reload-inventory-v1"
local MANIFEST_HEADER = "approved-reload-manifest-v1"
local APPROVAL_HEADER = "approved-reload-approval-v1"
local REQUIRED_FILES = {
  ["approved_reload.lua"] = true,
  ["init.lua"] = true,
}

local Controller = {}
Controller.__index = Controller

local function splitCanonicalLines(bytes, artifact)
  if type(bytes) ~= "string" then
    error(artifact .. " is unreadable")
  end
  if bytes:find("[\r\0]") then
    error(artifact .. " contains unsupported bytes")
  end
  if bytes:sub(-1) ~= "\n" then
    error(artifact .. " must end with a newline")
  end

  local lines = {}
  for line in bytes:gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function validateRuntimePath(path)
  if path == "" or path:sub(1, 1) == "/" or path:find("\\", 1, true) then
    error("unsafe runtime path: " .. path)
  end
  if not path:match("^[A-Za-z0-9._/-]+$") or path:sub(-4) ~= ".lua" then
    error("invalid runtime path: " .. path)
  end

  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      error("unsafe runtime path: " .. path)
    end
  end
  if path:find("//", 1, true) or path == "test" or path:match("^test/") or path:match("/test/") then
    error("invalid runtime path: " .. path)
  end
end

local function isDigest(value)
  return type(value) == "string" and value:match("^[0-9a-f]+$") ~= nil and #value == 64
end

local function joinPath(base, relative)
  if base == "" then
    return relative
  end
  return base .. "/" .. relative
end

function M.parseInventory(bytes)
  local lines = splitCanonicalLines(bytes, "reload-inventory")
  if lines[1] ~= INVENTORY_HEADER or #lines < 2 then
    error("invalid reload-inventory header")
  end

  local files = {}
  local seen = {}
  local previous = nil
  for i = 2, #lines do
    local path = lines[i]
    validateRuntimePath(path)
    if seen[path] or (previous ~= nil and previous >= path) then
      error("reload-inventory paths must be unique and sorted")
    end
    seen[path] = true
    previous = path
    table.insert(files, path)
  end

  for path in pairs(REQUIRED_FILES) do
    if not seen[path] then
      error("reload-inventory is missing " .. path)
    end
  end
  return files
end

function M.parseManifest(bytes, inventory)
  local lines = splitCanonicalLines(bytes, "reload-manifest")
  if lines[1] ~= MANIFEST_HEADER or #lines ~= #inventory + 1 then
    error("reload-manifest does not match reload-inventory")
  end

  local hashes = {}
  for i, expectedPath in ipairs(inventory) do
    local digest, path = lines[i + 1]:match("^([0-9a-f]+)\t(.+)$")
    if not isDigest(digest) or path ~= expectedPath or hashes[path] ~= nil then
      error("invalid reload-manifest entry for " .. expectedPath)
    end
    hashes[path] = digest
  end
  return hashes
end

function M.parseApproval(bytes)
  local lines = splitCanonicalLines(bytes, "reload-approval")
  if #lines ~= 2 or lines[1] ~= APPROVAL_HEADER or not isDigest(lines[2]) then
    error("invalid reload-approval")
  end
  return lines[2]
end

local function sameFiles(actual, expected)
  if #actual ~= #expected then
    return false
  end
  for i, path in ipairs(expected) do
    if actual[i] ~= path then
      return false
    end
  end
  return true
end

local function sameSnapshot(a, b)
  if a.identity ~= b.identity or a.inventoryDigest ~= b.inventoryDigest or a.manifestDigest ~= b.manifestDigest then
    return false
  end
  if #a.files ~= #b.files then
    return false
  end
  for i, file in ipairs(a.files) do
    local other = b.files[i]
    if other == nil or file.path ~= other.path or file.hash ~= other.hash then
      return false
    end
  end
  return true
end

function Controller:verify()
  local ok, snapshot = pcall(function()
    local inventoryBytes = self.deps.readFile(joinPath(self.configdir, "reload-inventory"))
    local manifestBytes = self.deps.readFile(joinPath(self.configdir, "reload-manifest"))
    local approvalBytes = self.deps.readFile(joinPath(self.configdir, "reload-approval"))
    local inventory = M.parseInventory(inventoryBytes)
    local hashes = M.parseManifest(manifestBytes, inventory)
    local identity = M.parseApproval(approvalBytes)

    if self.deps.hashBytes(manifestBytes) ~= identity then
      error("reload-approval does not match reload-manifest")
    end

    local discovered = self.deps.discoverLuaFiles(self.configdir)
    table.sort(discovered)
    if not sameFiles(discovered, inventory) then
      error("deployed Lua files do not match reload-inventory")
    end

    local files = {}
    for _, path in ipairs(inventory) do
      local hash = self.deps.hashFile(joinPath(self.configdir, path))
      if hash ~= hashes[path] then
        error("deployed hash mismatch for " .. path)
      end
      table.insert(files, { path = path, hash = hash })
    end

    return {
      identity = identity,
      inventoryDigest = self.deps.hashBytes(inventoryBytes),
      manifestDigest = self.deps.hashBytes(manifestBytes),
      files = files,
    }
  end)
  if not ok then
    return nil
  end
  return snapshot
end

function Controller:cancelTimers()
  if self.debounceTimer ~= nil then
    self.debounceTimer:stop()
    self.debounceTimer = nil
  end
  if self.verifyTimer ~= nil then
    self.verifyTimer:stop()
    self.verifyTimer = nil
  end
end

function Controller:changed()
  self.generation = self.generation + 1
  local generation = self.generation
  self:cancelTimers()
  self.debounceTimer = self.deps.doAfter(self.debounceSeconds, function()
    self.debounceTimer = nil
    local first = self:verify()
    if first == nil or first.identity == self.activeIdentity then
      return
    end

    self.verifyTimer = self.deps.doAfter(self.verifyDelaySeconds, function()
      self.verifyTimer = nil
      if self.generation ~= generation then
        return
      end
      local second = self:verify()
      if second == nil or not sameSnapshot(first, second) then
        return
      end

      self.activeIdentity = second.identity
      self.deps.reload()
    end)
  end)
end

function Controller:start()
  local initial = self:verify()
  self.activeIdentity = initial and initial.identity or nil
  self.watcher = self.deps
    .newWatcher(self.configdir, function()
      self:changed()
    end)
    :start()
  return self
end

function M.new(options)
  options = options or {}
  assert(options.deps, "approved reload dependencies are required")
  return setmetatable({
    configdir = options.configdir or "",
    debounceSeconds = options.debounceSeconds or 0.5,
    verifyDelaySeconds = options.verifyDelaySeconds or 0.25,
    deps = options.deps,
    generation = 0,
  }, Controller)
end

local function defaultReadFile(path)
  local file, err = io.open(path, "rb")
  if file == nil then
    error(err)
  end
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function defaultHashBytes(bytes)
  local hash = hs.hash.new("SHA256")
  hash:append(bytes)
  hash:finish()
  return hash:value()
end

local function discoverLuaFiles(configdir)
  local files = {}

  local function walk(relative)
    local directory = relative == "" and configdir or joinPath(configdir, relative)
    for name in hs.fs.dir(directory) do
      if name ~= "." and name ~= ".." then
        local path = relative == "" and name or relative .. "/" .. name
        local fullPath = joinPath(configdir, path)
        local linkMode = hs.fs.symlinkAttributes(fullPath, "mode")
        if linkMode == "link" then
          error("symlinks are not allowed in Hammerspoon runtime files: " .. path)
        end

        local mode = hs.fs.attributes(fullPath, "mode")
        if mode == "directory" then
          if path ~= "test" and not path:match("/test$") then
            walk(path)
          end
        elseif path:sub(-4) == ".lua" then
          if mode ~= "file" then
            error("runtime Lua path is not a regular file: " .. path)
          end
          table.insert(files, path)
        end
      end
    end
  end

  walk("")
  table.sort(files)
  return files
end

function M.start(options)
  options = options or {}
  options.deps = options.deps
    or {
      readFile = defaultReadFile,
      hashBytes = defaultHashBytes,
      hashFile = function(path)
        return hs.hash.forFile("SHA256", path)
      end,
      discoverLuaFiles = discoverLuaFiles,
      newWatcher = function(path, callback)
        return hs.pathwatcher.new(path, callback)
      end,
      doAfter = function(delay, callback)
        return hs.timer.doAfter(delay, callback)
      end,
      reload = hs.reload,
    }
  return M.new(options):start()
end

return M
