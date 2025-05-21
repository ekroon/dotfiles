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
        solargraph = { mason = false },
        sorbet = { mason = false },
        rubocop = { mason = false },
        ruby_lsp = { mason = false, cmd = { vim.fn.expand("ruby-lsp") } },
      },
      setup = {
        sorbet = function()
          require("lspconfig").sorbet.setup({
            cmd = { "bin/srb", "tc", "--lsp" },
            filetypes = { "ruby" },
          })
          return true
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
