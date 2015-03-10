# Special dircolors
if [ -r ~/.dircolors ]; then
  eval `dircolors ~/.dircolors`
fi

# Derek's Linux aliases
if [ $(uname -s) != "Darwin" ]; then
  alias ack='ack-grep'
fi

# Derek's OSX aliases
if [ $(uname -s) = "Darwin" ]; then
  alias emacs='/Applications/Emacs.app/Contents/MacOS/Emacs'
  alias emacsclient='/Applications/Emacs.app/Contents/MacOS/bin/emacsclient'
  export EDITOR="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
  export PATH=$PATH:/usr/local/texlive/2014basic/bin/x86_64-darwin
  alias tar='gtar'
fi

alias cstags='ctags -eR --languages="c#"'
alias cssh='~/.oh-my-zsh/custom/tmux-cssh/tmux-cssh -ss synchome.sh'
alias ctags='ctags --languages=scala,java,python,puppet -R'
alias curlapi="curl -H 'Content-Type: application/json'"
alias egrep='egrep --color=auto'
alias etags='ctags -e --languages=scala,java,python,puppet -R'
alias fgrep='fgrep --color=auto'
alias gfa='git fetch --all -p'
alias go='git checkout'
alias grep='grep --color=auto'
alias l='ls -CF'
alias la='ls -la'
alias la='ls -la'
alias ll='ls -l'
alias ls='ls --color=auto'
alias mv='mv -i'
alias revelation='keepassx'
alias sbt='nocorrect sbt'
alias scp='rsync -vazP'
alias screen='runtmux'
alias syh='synchome.sh'
alias tmux='runtmux'
alias top='htop'
alias vi="$EDITOR"

# I want globbing with rsync, prezto
unalias rsync

# Enable ssh-style host completion for syh
compdef _hosts synchome.sh

export MAVEN_OPTS="-Xmx512m -XX:MaxPermSize=128m"

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

ppv () {
  puppet parser validate --verbose ${1:-~/SimpleEnergy/Systems/puppet}/**/*.pp
}

# Automatically quote globs in URL and remote references (http://superuser.com/a/431568)
__remote_commands=(scp rsync)
zstyle -e :urlglobber url-other-schema '[[ $__remote_commands[(i)$words[1]] -le ${#__remote_commands} ]] && reply=("*") || reply=(http https ftp)'

# I DON'T WANT CRAZY WORDS
autoload -U select-word-style
select-word-style bash
WORDCHARS=""

# Get rid of prezto's poor editor decisions
unset VISUAL

# Fix up the sorin prompt the way I like it
PROMPT='${SSH_TTY:+"%F{red}%n%f@%F{yellow}%m%f "}%F{cyan}${_prompt_sorin_pwd}%f${git_info:+${(e)git_info[prompt]}}%(!. %B%F{red}#%f%b.)${git_info[rprompt]}${editor_info[keymap]} '
#RPROMPT='${editor_info[overwrite]}%(?:: %F{red}⏎%f)${VIM:+" %B%F{green}V%f%b"}${INSIDE_EMACS:+" %B%F{green}E%f%b"}'
unset RPROMPT

# Use prezto LESS settings, without -S (I like folded lines)
export LESS='-F -g -i -M -R -X -z-4'


# boot2docker is *such* a pain: https://github.com/boot2docker/boot2docker/issues/628#issuecomment-68909772
DOCKER_HOST=tcp://127.0.0.1:2376
DOCKER_CERT_PATH=/Users/dchenbecker/.boot2docker/certs/boot2docker-vm
DOCKER_TLS_VERIFY=1
