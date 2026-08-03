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
