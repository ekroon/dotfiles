if [[ "$IS_AGENT" == "1" ]]; then
    unset ZSH_THEME
    PROMPT="🤖 %1~ %# "
else
    if (( $+commands[starship] )); then
        # ignore oh-my-zsh theme
        unset ZSH_THEME

        eval "$(starship init zsh)"
    else
        echo '[oh-my-zsh] starship not found, please install it from https://starship.rs'
    fi
fi
