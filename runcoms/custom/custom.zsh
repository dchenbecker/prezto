# Derek's OSX aliases
if [ "$(uname -s)" = "Darwin" ]; then
  alias emacs='/Applications/Emacs.app/Contents/MacOS/Emacs'
  alias emacsclient='/Applications/Emacs.app/Contents/MacOS/bin/emacsclient'
  export EDITOR="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
  export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
  export MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$PATH"
  alias tar='gtar'
  alias dircolors='gdircolors'
else
  alias sbt='nocorrect sbt'
fi

# Add Nix if available
if [ -d "/nix/var/nix/profiles/default/bin" ]; then
    path+=/nix/var/nix/profiles/default/bin
    path+=~/.nix-profile/bin
fi

# Add asdf if available
if [ -f ~/.asdf/asdf.sh ]; then
    source ~/.asdf/asdf.sh
fi

# We want Rust tools in our path (e.g. rg, eza)
if [ -d "$HOME/.cargo/bin" ]; then
    path+="$HOME/.cargo/bin"
fi

## Nicer cat/less replacement
if hash bat &>/dev/null; then
    alias cat="bat --pager=never"
    alias less="bat"
fi

## Nicer watch replacement
if hash viddy &>/dev/null; then
    alias watch="viddy"
fi

# Special dircolors
if [ -r ~/.dircolors ]; then
  eval "$(dircolors)"
fi

# Try out eza for a while and see if we like it...
if hash eza &>/dev/null; then
    LS_COMMAND=eza
    alias ls='eza'
    alias l='eza -F'
    alias tree='eza -T'
else
    LS_COMMAND=ls
    alias ls='ls --color=auto'
    alias l='ls -CF'
fi

alias la="$LS_COMMAND -la"
alias ll="$LS_COMMAND -l"

# Better cp if it exists
if hash xcp &> /dev/null; then
    alias cp=xcp
fi

# Better find if it exists
if hash fd &> /dev/null; then
    alias find=fd
fi

# Use the fork of youtube-dl if it exists
if hash yt-dlp &> /dev/null; then
    alias youtube-dl=yt-dlp
fi

alias cstags='ctags -eR --languages="c#"'
alias cssh='~/.oh-my-zsh/custom/tmux-cssh/tmux-cssh -ss synchome.sh'
alias ctags='ctags --languages=scala,java,python,puppet,kotlin,rust -R --exclude=.ensime_cache --exclude=.tox --exclude=.git'
alias curlapi="curl -H 'Content-Type: application/json'"
alias egrep='egrep --color=auto'
alias etags='ctags -e'
alias fgrep='fgrep --color=auto'
alias gfa='git fetch --all -p'
alias go='git checkout'
alias grep='grep --color=auto'
alias mv='mv -i'
alias qe="emacs -q -nw"
alias revelation='keepassx'
alias scp='rsync -vazP'
alias screen='runtmux'
alias syh='synchome.sh'
alias tmux='runtmux'
alias top='htop'
alias vi="\$EDITOR"
alias qp="qpdfview"

# Make emacs start a new server if it's not already running
export ALTERNATE_EDITOR=""

# I want globbing with rsync, prezto
unalias rsync

# Enable ssh-style host completion for syh
compdef _hosts synchome.sh

### The rest is key bindings ###

# Set emacs bindings first
bindkey -e

autoload -U backward-kill-word-match
zle -N backward-kill-word-space backward-kill-word-match 
zstyle ':zle:backward-kill-word-space' word-style space
bindkey '^W' backward-kill-word-space

# Customize arrow key movement with mods
bindkey "^[[1;3C" forward-word
bindkey "^[[1;5C" vi-forward-blank-word
bindkey "^[[1;3D" backward-word
bindkey "^[[1;5D" vi-backward-blank-word

# Use patterns for history search
bindkey '^R' history-incremental-pattern-search-backward

# Automatically quote globs in URL and remote references (http://superuser.com/a/431568)
__remote_commands=(scp rsync)
zstyle -e :urlglobber url-other-schema '[[ $__remote_commands[(i)$words[1]] -le ${#__remote_commands} ]] && reply=("*") || reply=(http https ftp)'

# I DON'T WANT CRAZY WORDS
autoload -U select-word-style
select-word-style bash
WORDCHARS=""

# Fix up the sorin prompt the way I like it (but not on the terminal)
if [[ $TERM != "linux" ]]; then
    export PROMPT='${SSH_TTY:+"%F{red}%n%f@%F{yellow}%m%f "}%F{cyan}${_prompt_sorin_pwd}%f${git_info:+${(e)git_info[prompt]}}%(!. %B%F{red}#%f%b.)${git_info[rprompt]}${editor_info[keymap]} '
    unset RPROMPT
else
    prompt sorin
fi

# Use prezto LESS settings, without -S (I like folded lines)
export LESS='-F -g -i -M -R -X -z-4'

# SBT settings, because the Typesafe launcher is borken
export SBT_OPTS="-Xms512M -Xmx8G -Xss1M -XX:MaxMetaspaceSize=2G"

# Use ghcup for Haskell stuff if available
if [ -r ~/.ghcup/env ]; then
    source ~/.ghcup/env
fi

# Set up Nix env if available
if [ -r ~/.nix-profile/etc/profile.d/nix.sh ]; then
    source ~/.nix-profile/etc/profile.d/nix.sh
fi

# Set up autocd if possible
[ -d ~/.cdpath ] && export cdpath=(~/.cdpath /home/software/projects/)
