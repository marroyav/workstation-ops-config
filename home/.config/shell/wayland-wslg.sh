# shellcheck shell=sh
# Wayland-first defaults for GUI applications launched from WSL shells.
# WSLg still exposes XWayland, so toolkits can fall back when necessary.
if [ -n "${WSL_DISTRO_NAME:-}" ] &&
   [ -S "${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}/${WAYLAND_DISPLAY:-wayland-0}" ]; then
  export XDG_SESSION_TYPE=wayland
  export GDK_BACKEND='wayland,x11'
  export QT_QPA_PLATFORM='wayland;xcb'
  export SDL_VIDEODRIVER='wayland,x11'
  export MOZ_ENABLE_WAYLAND=1
  export ELECTRON_OZONE_PLATFORM_HINT=wayland
  export NIXOS_OZONE_WL=1

  # Select WSL's D3D12 Gallium driver explicitly. The integrated GPU avoids
  # discrete-GPU copy overhead in WSLg's presentation path and is a good
  # default for desktop UI.
  export GALLIUM_DRIVER=d3d12
  export MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel
fi
