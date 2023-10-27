# Derek's OSX aliases
if [ "$(uname -s)" = "Darwin" ]; then
  alias emacs='/Applications/Emacs.app/Contents/MacOS/Emacs'
  alias emacsclient='/Applications/Emacs.app/Contents/MacOS/bin/emacsclient'

  export path=(
      ~/.nodenv/shims
      /opt/homebrew/bin
      /opt/homebrew/opt/coreutils/libexec/gnubin
      $path
      /usr/local/texlive/2023/bin/universal-darwin
      /Applications/Wireshark.app/Contents/MacOS
  )

  export manpath=(
      /opt/homebrew/opt/coreutils/libexec/gnuman
      /opt/homebrew/share/man
      /usr/share/man
  )

  export EMACS_SOCKET_NAME=/tmp/${USER}/emacs${UID}/server
  export EDITOR="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
  alias en="${EDITOR} -nw"
  export VISUAL="$EDITOR"

  alias tar='gtar'
  alias dircolors='gdircolors'
else
  alias sbt='nocorrect sbt'
fi

# Simple Java aliases
# Maybe switch to https://github.com/protocol7/javaenv at some point
alias jdk11='export JAVA_HOME=/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home'

# We want Rust tools in our path (e.g. rg, exa)
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

# Try out exa for a while and see if we like it...
if hash exa &>/dev/null; then
    LS_COMMAND=exa
    alias ls='exa'
    alias l='exa -F'
    alias tree='exa -T'
else
    LS_COMMAND=ls
    alias ls='ls --color=auto'
    alias l='ls -CF'
fi

alias la="$LS_COMMAND -la"
alias ll="$LS_COMMAND -l"

alias cstags='ctags -eR --languages="c#"'
alias cssh='~/.oh-my-zsh/custom/tmux-cssh/tmux-cssh -ss synchome.sh'
alias ctags='ctags --languages=scala,java,python,puppet,kotlin -R --exclude=.ensime_cache --exclude=.tox --exclude=.git'
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

# Use prezto LESS settings, without -S (I like folded lines)
export LESS='-F -g -i -M -R -X -z-4'

# SBT settings, because the Typesafe launcher is borken
export SBT_OPTS="-Xms512M -Xmx8G -Xss1M -XX:MaxMetaspaceSize=2G"

# Set cdpath for useful locations
export cdpath=(~/Documents ~/Downloads ~/Repos ~/Tools ~/.cdpath)

# Set up asdf if available
[[ -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]] && {
    . /opt/homebrew/opt/asdf/libexec/asdf.sh
}
