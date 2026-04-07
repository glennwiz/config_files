[[ $- != *i* ]] && return

source ~/.local/share/omarchy/default/bash/rc

bind 'set enable-bracketed-paste off'
export PATH="$PATH:/home/glennwiz/dev/Odin"
alias vim='nvim'
alias lg='lazygit'
alias cdd='cd ~/dev/'
eval "$(oh-my-posh init bash --config ~/.config/.mytheme.omp.json)"

#
# Prefer .NET from ~/.dotnet over mise
if [ -d "$HOME/.dotnet" ]; then
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$DOTNET_ROOT:$PATH"
fi

export PATH="$HOME/.local/bin:$PATH"

complete -C /usr/bin/terraform terraform

# opencode
export PATH=/home/glennwiz/.opencode/bin:$PATH
