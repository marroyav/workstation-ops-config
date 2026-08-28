# WSLg Wayland and Graphics Notes

The workstation runs Debian 12 under WSL2/WSLg. WSLg exposes both a native
Wayland socket and XWayland. The configuration prefers native Wayland for
normal desktop UI but deliberately preserves X11 as a fallback.

## Defaults

`home/.config/shell/wayland-wslg.sh` sets Wayland-first values for applications
started from a shell:

- GTK: `GDK_BACKEND=wayland,x11`
- Qt: `QT_QPA_PLATFORM=wayland;xcb`
- SDL: `SDL_VIDEODRIVER=wayland,x11`
- Firefox-family applications: `MOZ_ENABLE_WAYLAND=1`
- Electron: `ELECTRON_OZONE_PLATFORM_HINT=wayland`
- Mesa: `GALLIUM_DRIVER=d3d12`
- Default adapter: integrated Intel GPU

The corresponding `environment.d` file covers launchers that consume the
standard user environment configuration. Brave has a dedicated desktop entry
and wrapper that add `--ozone-platform=wayland`.

## Why X11 Remains Available

Measurements on this workstation on 2026-08-28 showed:

- The Wayland socket is active.
- XWayland OpenGL reports `D3D12 (Intel(R) UHD Graphics)` and
  `Accelerated: yes`.
- The native Wayland protocol advertised by WSLg does not include Linux
  DMA-BUF.
- Native Wayland EGL therefore reports the software `swrast` driver for some
  applications.

Wayland can still provide better input, scaling, and window-system behavior,
but it is not automatically faster for GPU-heavy applications in this WSLg
configuration.

Use these explicit fallbacks when an application is slow or renders
incorrectly:

```bash
brave-x11
gui-x11 APPLICATION
```

## Diagnostics

Confirm that WSLg exposes Wayland:

```bash
printf '%s\n' "$WAYLAND_DISPLAY"
test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" && echo 'Wayland is available'
wayland-info
```

Check the accelerated XWayland renderer:

```bash
glxinfo -B
```

Expected key lines:

```text
Device: D3D12 (Intel(R) UHD Graphics)
Accelerated: yes
OpenGL renderer string: D3D12 (Intel(R) UHD Graphics)
```

Run the repository-wide check with:

```bash
scripts/check-dev-environment.sh
```

## External References

- WSLg project and GPU architecture: <https://github.com/microsoft/wslg>
- Microsoft WSL GUI application guide:
  <https://learn.microsoft.com/windows/wsl/tutorials/gui-apps>
- Chromium Ozone platform documentation:
  <https://chromium.googlesource.com/chromium/src/+/HEAD/docs/ozone_overview.md>
