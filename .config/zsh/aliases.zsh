alias apt='sudo apt'
alias aptu='apt update && apt full-upgrade -y'
alias docker='sudo docker'
zh() { LANG=zh_CN.UTF-8 "$@"; }

alias eza='eza -g --git'
alias l='eza -lah'
alias ll='eza -lh'
alias vi=vim

if command -v code > /dev/null 2>&1
then
    alias code.='code .'
    alias code。=code.
fi

if command -v batcat > /dev/null 2>&1
then
    alias bat=batcat
    alias cat='bat -pp'
fi
alias fd=fdfind
alias gxx=g++

if command -v pnpm > /dev/null 2>&1
then
    alias npm=pnpm
    alias npx='pnpm dlx'
fi
