#!/usr/bin/zsh 

# Set cdpath for useful locations
export cdpath=(~/Documents ~/Repos ~/tools)

GPG_TTY=$(tty)
export GPG_TTY

# SonarQube setup
if [ -f ~/.sonarlint/token ]; then
    export SONAR_TOKEN=$(< ~/.sonarlint/token )
fi

# For windows, WSL2 needs some help on scaling
export GDK_DPI_SCALE=1.75

# Alias to simplify opening things in Windows from WSL
fun winopen() {
    /mnt/c/Windows/explorer.exe $(wslpath -w $1)
}

# Use Windows Chrome for browser URLs from WSL2
export BROWSER="/mnt/c/PROGRA~1/Google/Chrome/Application/chrome.exe"

# Ensure font settings and keyboard maps for X11
export DISPLAY=localhost:0
xmodmap ~/.zprezto/runcoms/byhost/Xmodmap.CSCO
xmodmap ~/.zprezto/runcoms/byhost/Xmodmap.rightalt
xrdb -merge ~/.zprezto/runcoms/byhost/Xresources.CSCO

# Override so that we use the right socket
export EDITOR="emacsclient -s /tmp/realdcb/emacs1000/server -nw -c"
export VISUAL="$EDITOR"
