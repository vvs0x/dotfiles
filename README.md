<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/305954de-a835-48d6-b936-efa2be73953b" alt="Logo" width="150">
  <br>Dotfiles
</p>
</h1>

My macOS configuration files, centered around a keyboard-driven workflow.

## The Core Idea

I use **Karabiner-Elements** to remap Caps Lock to `Ctrl + Option + Cmd`. This turns Caps Lock into a dedicated modifier key — a "hyper key" — that never conflicts with any native macOS shortcuts. **AeroSpace** then uses this hyper key for all its window management bindings, giving me a clean, conflict-free keyboard layer.

## What's Inside

### [AeroSpace](https://github.com/nikitabobko/AeroSpace) — Tiling Window Manager

A keyboard-driven tiling window manager for macOS. My setup includes:

- **6 workspaces** (`A` `S` `D` `F` `G` `T`) — switched with `Hyper + key`
- **Vim-style navigation** — `Hyper + Shift + HJKL` to focus, `Hyper + HJKL` to move windows
- **App launchers** — `Hyper + Enter` for Ghostty, `Hyper + V` for VS Code, `Hyper + C` for Claude, etc.
- **Auto-assignment** — apps open in their designated workspace (Obsidian → `A`, VS Code/RStudio → `D`, messaging → `G`)
- **Floating exceptions** — Finder, System Preferences, and Activity Monitor float by default
- **Dual monitor** — workspaces `G` and `T` are assigned to an LG ULTRAGEAR

### [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) — Keyboard Remapping

Turns the keyboard into something that makes sense:

- **Caps Lock → Hyper Key** (`Ctrl + Option + Cmd`) — the foundation for all AeroSpace shortcuts
- **Right Command → Fn + Ctrl** — used as a secondary modifier layer
- **Fn + Ctrl + HJKL → Arrow Keys** — vim-style navigation everywhere on macOS
- **Fn + Ctrl + Enter → Cmd + O** — quick "open folder" shortcut in Finder
- **Both Shifts → Toggle Caps Lock** — when you actually need Caps Lock

### [Ghostty](https://github.com/ghostty-org/ghostty) — Terminal Emulator

- **Font**: MonoLisa Variable (size 12, ligatures disabled)
- **Style**: 75% opacity with background blur, underline blinking cursor
- **Behavior**: copy-on-select, glass icon on macOS

### [Neovim](https://github.com/neovim/neovim) — Text Editor

Minimal config — just a `jj` → `Escape` mapping in insert mode.
