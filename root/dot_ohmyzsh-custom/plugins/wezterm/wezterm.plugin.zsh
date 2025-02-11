source "$ZSH_CUSTOM/plugins/wezterm/wezterm.sh"

# if HOSTNAME is empty set it to the output of hostname
if [ -z "$HOSTNAME" ]; then
  HOSTNAME=$(hostname)
fi
