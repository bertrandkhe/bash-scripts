#!/bin/bash

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y \
	curl \
	jq \
	git \
	ca-certificates \
	gnupg \
	fzf \
	chafa \
	imagemagick \
	ripgrep

has_nvim="$(which nvim)"
if [[ "$has_nvim" = "" ]]; then
	curl -L https://github.com/neovim/neovim/releases/download/stable/nvim.appimage -o /tmp/nvim.appimage
	chmod +x /tmp/nvim.appimage
	/tmp/nvim.appimage --appimage-extract
	sudo mv squashfs-root /opt/nvim
	sudo ln -s /opt/nvim/AppRun /usr/bin/nvim
	git clone https://github.com/bertrandkhe/nvim-config2.git ~/.config/nvim
fi

has_zsh="$(which zsh)"
if [[ "$has_zsh" = "" ]]; then
	sudo apt-get install -y zsh
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
if [[ ! -d $NVM_DIR ]]; then
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
	[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
	nvm install 18
fi

npm install -g typescript \
	typescript-language-server \
	bash-language-server \
	vscode-langservers-extracted \
	@tailwindcss/language-server \
	yaml-language-server \
	yarn \
	prettier \
	lua-fmt \
	nginxbeautifier

has_tmux="$(which tmux)"
if [[ "$has_tmux" = "" ]]; then
	sudo apt-get install -y tmux
	# https://github.com/tmux-plugins/tpm
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
	cat <<EOF > $HOME/.tmux.conf
set -sg escape-time 10
setw -g mode-keys vi

set  -g default-terminal "tmux-256color"
set-option -sa terminal-overrides 'xterm-256color:RGB'
set-option -g focus-events on

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'aserowy/tmux.nvim'
set -g @plugin 'erikw/tmux-powerline'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF
	~/.tmux/plugins/tpm/bin/install_plugins
fi

has_docker="$(which docker)"
if [[ "$has_docker" = "" ]]; then
	curl -fsSL https://get.docker.com -o get-docker.sh
	sudo sh get-docker.sh
fi
