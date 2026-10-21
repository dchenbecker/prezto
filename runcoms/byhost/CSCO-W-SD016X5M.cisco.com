#!/usr/bin/zsh 

# Set cdpath for useful locations
export cdpath=(~/Documents ~/Repos ~/tools)

# SonarQube setup
if [ -f ~/.sonarlint/token ]; then
    export SONAR_TOKEN=$(< ~/.sonarlint/token )
fi

# WSL2 needs some help on scaling; VcXsrv provides X11
WSL_DPI_SCALE=1.75
. ~/.zprezto/runcoms/wsl/wsl-x11
