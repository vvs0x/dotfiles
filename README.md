<h1 align="center">
  Dotfiles
</h1>

MacOS dotfiles built around a keyboard-driven workflow. Caps Lock is remapped to `ctrl + option + cmd` via Karabiner-Elements, creating a dedicated modifier key that never conflicts with native macOS shortcuts. AeroSpace picks up this hyper key for all window management bindings, keeping everything on a clean, conflict-free keyboard layer.

## What's Inside

### [AeroSpace](https://github.com/nikitabobko/AeroSpace) — Tiling Window Manager

- 6 workspaces (`A` `S` `D` `F` `G` `T`), switched with `Hyper + key`
- Vim-style `HJKL` to move windows, `Hyper + Shift + HJKL` to shift focus
- App launchers: `Hyper + Enter` Ghostty · `Hyper + V` VS Code · `Hyper + E` Zed · `Hyper + C` Claude · `Hyper + R` RStudio · `Hyper + Shift + O` Obsidian
- Apps auto-open in their workspace (Obsidian in `A`, editors/RStudio in `D`, messaging in `G`)
- Finder, System Settings, Activity Monitor and VPN clients float by default
- Workspaces `F` `G` `T` are pinned to the external monitor (EV3895), falling back to the LG UltraGear
- Service mode (`Hyper + Shift + M`) to reload config, flatten the tree, or toggle floating

### [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) — Keyboard Remapping

- Caps Lock becomes `Ctrl + Option + Cmd` (the Hyper key that drives AeroSpace)
- Right Command becomes `Fn + Ctrl` (a secondary modifier layer)
- `Fn + Ctrl + HJKL` for arrow keys everywhere on macOS
- `Fn + Ctrl + Enter` opens the current folder in Finder
- Both Shifts together toggle real Caps Lock

### [Ghostty](https://github.com/ghostty-org/ghostty) — Terminal Emulator

- Zed Mono Bold, size 15
- Catppuccin Frappé palette
- 8px window padding, minimal title bar
- Launches Nushell as the default shell

### [Nushell](https://www.nushell.sh) — Shell

- Structured-data shell that replaced zsh and fish
- Wired in as Ghostty's default command

### [Helix](https://github.com/helix-editor/helix) — Text Editor

- Catppuccin Frappé theme, relative line numbers, 100-column ruler
- LSPs wired up: basedpyright + ruff (Python), rust-analyzer with clippy, texlab (LaTeX), marksman (Markdown)
- `jj` to Escape in insert mode, `Esc` collapses the selection

