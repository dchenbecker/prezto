# A function to cleanly handle tmux setup for simple cases, and allow for more complex ones as well
function runtmux() {
  DEFAULT_SESSION_DIR="$HOME/sessions"
  DEFAULT_SOCKET="$DEFAULT_SESSION_DIR/default"

  DEBUG=true

  if [[ "$1" == "-h" ]]; then
    echo "Usage: tmux [<relative socket name>|<absolute socket path>|<-tmux flags>]"
    return
  fi

  $DEBUG && echo "Starting with $# args"

  # Simplest case: no args or first arg is a flag (-*). Attach to or create $HOME/sessions/default
  if [[ $# == 0 || "$1" == -* ]]; then
    [[ -d "$DEFAULT_SESSION_DIR" ]] || mkdir -p "$DEFAULT_SESSION_DIR"

    if [ -e "$DEFAULT_SOCKET" ] && =tmux -S "$DEFAULT_SOCKET" has-session 2> /dev/null ; then
      $DEBUG && echo "Found existing socket with session: $DEFAULT_SOCKET"
      =tmux -2 -S "$DEFAULT_SOCKET" "$@" attach
    else
      $DEBUG && echo "Starting new session on $DEFAULT_SOCKET"
      =tmux -2 -S "$DEFAULT_SOCKET" "$@" new
    fi

    return
  fi

  TMUX_SOCKET_NAME="$1"
  shift 1

  # Second case, the first arg is a name. This will either be an absolute socket path, or one relative to the default session
  # dir. If you want session names, provide args
  if [[ "$TMUX_SOCKET_NAME" != /* ]]; then
    [[ -d "$DEFAULT_SESSION_DIR" ]] || mkdir -p "$DEFAULT_SESSION_DIR"
    TMUX_SOCKET_NAME="$DEFAULT_SESSION_DIR/$TMUX_SOCKET_NAME"
  fi

  $DEBUG && echo "Looking for non-default socket: $TMUX_SOCKET_NAME"

  if [ -e "$TMUX_SOCKET_NAME" ] && =tmux -S "$TMUX_SOCKET_NAME" has-session 2> /dev/null ; then
    $DEBUG && echo "Found existing socket with session: $TMUX_SOCKET_NAME"
    =tmux -2 -S "$TMUX_SOCKET_NAME" "$@" attach
  else
    $DEBUG && echo "Starting new session on $TMUX_SOCKET_NAME"
    =tmux -2 -S "$TMUX_SOCKET_NAME" "$@" new
  fi
}

