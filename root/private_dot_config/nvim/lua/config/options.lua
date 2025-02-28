-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.lazyvim_picker = "fzf"

if vim.fn.getenv("GITHUB_REPOSITORY") == "github/github" then
  vim.g.lazyvim_ruby_lsp = "invalid"
  vim.g.lazyvim_ruby_formatter = "rubocop"
else
  vim.g.lazyvim_ruby_lsp = "ruby_lsp"
  vim.g.lazyvim_ruby_formatter = "rubocop"
end
