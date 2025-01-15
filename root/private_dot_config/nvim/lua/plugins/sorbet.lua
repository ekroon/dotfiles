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
      },
      setup = {
        sorbet = function()
          require("lspconfig").sorbet.setup({
            cmd = { "bin/srb", "tc", "--lsp" },
            filetypes = { "ruby" },
          })
        end,
      },
    },
  },
}
