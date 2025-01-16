return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "ruby" } },
  },
  {
    "neovim/nvim-lspconfig",
    ---@class PluginLspOpts
    opts = {
      servers = {
        -- pyright will be automatically installed with mason and loaded with lspconfig
        sorbet = {},
        rubocop = { mason = false },
      },
      setup = {
        sorbet = function()
          require("lspconfig").sorbet.setup({
            cmd = { "bin/srb", "tc", "--lsp" },
            filetypes = { "ruby" },
          })
        end,
        rubocop = function()
          require("lspconfig").rubocop.setup({
            cmd = { "rubocop", "--lsp" },
            filetypes = { "ruby" },
          })
          return true
        end,
      },
    },
  },
}
