<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/305954de-a835-48d6-b936-efa2be73953b" alt="Logo" width="150">
  <br>Dotfiles
</p>
</h1>

My macOS configuration files, centered around a keyboard-driven workflow.

## The Core Idea

I use **Karabiner-Elements** to remap Caps Lock to `Ctrl + Option + Cmd`. This turns Caps Lock into a dedicated modifier key that never conflicts with any native macOS shortcuts. **AeroSpace** then uses this hyper key for all its window management bindings, giving me a clean, conflict-free keyboard layer.

## What's Inside

### [AeroSpace](https://github.com/nikitabobko/AeroSpace) — Tiling Window Manager

A keyboard-driven tiling window manager for macOS. My setup includes **6 workspaces** (`A` `S` `D` `F` `G` `T`) switched with `Hyper + key`. Windows are moved and focused using **vim-style bindings** with `HJKL`. Apps open in their designated workspace automatically (Obsidian in `A`, VS Code and RStudio in `D`, messaging in `G`). Finder, System Preferences, and Activity Monitor float by default. Workspaces `G` and `T` are assigned to an external LG ULTRAGEAR monitor.

There are also quick **app launchers** built in: `Hyper + Enter` for Ghostty, `Hyper + V` for VS Code, `Hyper + C` for Claude, and a few more.

### [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) — Keyboard Remapping

Turns the keyboard into something that makes sense. **Caps Lock** becomes a Hyper Key (`Ctrl + Option + Cmd`), which is the foundation for all AeroSpace shortcuts. **Right Command** becomes `Fn + Ctrl`, a secondary modifier layer that gives me **vim-style arrow keys** with `HJKL` everywhere on macOS. Pressing **both Shifts** together toggles the actual Caps Lock for when you need it.

### [Ghostty](https://github.com/ghostty-org/ghostty) — Terminal Emulator

Running **MonoLisa Variable** at size 12 with ligatures disabled. The window sits at **75% opacity** with background blur. Underline blinking cursor, copy-on-select enabled, and the glass icon on macOS because it looks nice.

### [Neovim](https://github.com/neovim/neovim) — Text Editor

Minimal config. Just a `jj` to `Escape` mapping in insert mode.
