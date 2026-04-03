<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/305954de-a835-48d6-b936-efa2be73953b" alt="Logo" width="150">
  <br>Dotfiles
</p>
</h1>

MacOS dotfiles built around a keyboard-driven workflow. Caps Lock is remapped to `ctrl + option + cmd` via Karabiner-Elements, creating a dedicated modifier key that never conflicts with native macOS shortcuts. AeroSpace picks up this hyper key for all window management bindings, keeping everything on a clean, conflict-free keyboard layer.

## What's Inside

### [AeroSpace](https://github.com/nikitabobko/AeroSpace) — Tiling Window Manager

- 6 workspaces (`A` `S` `D` `F` `G` `T`), switched with `Hyper + key`
- Vim-style navigation with `HJKL` to focus and move windows
- App launchers: `Hyper + Enter` for Ghostty, `Hyper + V` for VS Code, `Hyper + C` for Claude, etc.
- Apps auto-open in their workspace (Obsidian in `A`, VS Code/RStudio in `D`, messaging in `G`)
- Finder, System Preferences, Activity Monitor float by default
- Workspaces `G` and `T` go to an external LG ULTRAGEAR

### [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) — Keyboard Remapping

- Caps Lock becomes `Ctrl + Option + Cmd` (the hyper key for AeroSpace)
- Right Command becomes `Fn + Ctrl` (secondary modifier layer)
- `Fn + Ctrl + HJKL` for arrow keys everywhere on macOS
- `Fn + Ctrl + Enter` for quick open folder in Finder
- Both Shifts together to toggle actual Caps Lock

### [Ghostty](https://github.com/ghostty-org/ghostty) — Terminal Emulator

- MonoLisa Variable, size 12, ligatures off
- 75% opacity with background blur
- Underline blinking cursor, copy-on-select, glass icon

### [Neovim](https://github.com/neovim/neovim) — Text Editor

Minimal config. Just `jj` to Escape in insert mode.
