# Minimal login-shell profile for WSL.
umask 022

if [ -d "$HOME/bin" ]; then
  PATH="$HOME/bin:$PATH"
fi

if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi

# Prefer native Wayland for WSLg applications, with toolkit-level X11
# fallbacks for applications that do not support Wayland yet.
if [ -r "$HOME/.config/shell/wayland-wslg.sh" ]; then
  . "$HOME/.config/shell/wayland-wslg.sh"
fi

# MIT Kerberos DIR caches need the backing directory to exist after WSL starts.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
  mkdir -p "$XDG_RUNTIME_DIR/krb5cc"
  chmod 700 "$XDG_RUNTIME_DIR/krb5cc"
fi

if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
if [ -r "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
