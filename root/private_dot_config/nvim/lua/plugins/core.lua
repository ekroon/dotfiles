local function get_darkmode_setting()
  -- local handle = io.popen("curl -s http://localhost:5000/apple-interface-style")
  -- if not handle then
  --   return "light"
  -- end
  -- local result = handle:read("*a")
  -- handle:close()
  --
  -- local success, json = pcall(vim.fn.json_decode, result)
  -- if success and json.AppleInterfaceStyle == "Dark" then
  --   return "dark"
  -- else
  --   return "light"
  -- end
  return "dark"
end

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
  {
    "f-person/auto-dark-mode.nvim",
    enabled = false,
    opts = {
      fallback = get_darkmode_setting(),
    },
  },
}
