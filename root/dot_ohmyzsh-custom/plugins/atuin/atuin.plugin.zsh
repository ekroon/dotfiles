if (( $+commands[atuin] )); then
  export ATUIN_NOBIND="true"
  eval "$(atuin init zsh)"
  bindkey '^r' _atuin_search_widget
else
  echo '[oh-my-zsh] atuin not found, please install it from https://atuin.sh/'
fi
