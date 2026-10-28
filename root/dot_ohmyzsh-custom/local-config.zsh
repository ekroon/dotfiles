# Machine-local configuration is intentionally not managed by chezmoi.
for local_config_file in "${XDG_CONFIG_HOME:-$HOME/.config}"/zsh/local.d/*.zsh(N.); do
  source "$local_config_file"
done
unset local_config_file
