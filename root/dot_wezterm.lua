-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

config.color_scheme = "catppuccin-latte"

config.font = wezterm.font("SauceCodePro Nerd Font", { weight = "Regular" })
config.font_size = 14
config.bold_brightens_ansi_colors = "BrightAndBold"

config.window_decorations = "RESIZE"

-- and finally, return the configuration to wezterm
return config
