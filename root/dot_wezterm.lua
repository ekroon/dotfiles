-- Pull in the wezterm API
local wezterm = require("wezterm")

-- wezterm.gui is not available to the mux server, so take care to
-- do something reasonable when this config is evaluated by the mux
local function get_appearance()
	-- if wezterm.gui then
	-- 	return wezterm.gui.get_appearance()
	-- end
	return "Dark"
end

local function scheme_for_appearance(appearance)
	if appearance:find("Dark") then
		return "catppuccin-mocha"
	else
		return "catppuccin-latte"
	end
end

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

config.color_scheme = scheme_for_appearance(get_appearance())

config.font = wezterm.font("SauceCodePro Nerd Font", { weight = "Regular" })
config.font_size = 13
config.bold_brightens_ansi_colors = "BrightAndBold"

config.window_decorations = "RESIZE"

local act = wezterm.action
config.keys = {
	-- Make Option-Left equivalent to Alt-b which many line editors interpret as backward-word
	{ key = "LeftArrow", mods = "OPT", action = act.SendString("\x1bb") },
	-- Make Option-Right equivalent to Alt-f; forward-word
	{ key = "RightArrow", mods = "OPT", action = act.SendString("\x1bf") },
	{
		key = "9",
		mods = "ALT",
		action = wezterm.action.ShowLauncherArgs({ flags = "FUZZY|DOMAINS|WORKSPACES" }),
	},
}

wezterm.add_to_config_reload_watch_list("~/.ssh/config")
wezterm.add_to_config_reload_watch_list("~/.ssh/codespaces")

config.ssh_domains = wezterm.default_ssh_domains()

-- and finally, return the configuration to wezterm
return config
