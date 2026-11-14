# XDG directory
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state
export XDG_CACHE_HOME=$HOME/.cache

export GPG_TTY=$TTY

if command -v nvim
then
    export EDITOR=nvim
	export VISUAL=nvim
else
    export EDITOR=vim
	export VISUAL=vim
fi

# rustup config
export RUSTUP_UPDATE_ROOT=https://mirror.nju.edu.cn/rustup/rustup
export RUSTUP_DIST_SERVER=https://mirror.nju.edu.cn/rustup

