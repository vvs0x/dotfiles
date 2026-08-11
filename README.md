<h1 align="center">
  Dotfiles
</h1>

MacOS dotfiles built around a keyboard-driven workflow. Caps Lock is remapped to `ctrl + option + cmd` via Karabiner-Elements, creating a dedicated modifier key that never conflicts with native macOS shortcuts. AeroSpace picks up this hyper key for all window management bindings, keeping everything on a clean, conflict-free keyboard layer.


### [AeroSpace](https://github.com/nikitabobko/AeroSpace) ![small text](https://img.shields.io/badge/-Tiling%20Window%20Manager-blue)

- 6 workspaces (`A` `S` `D` `F` `G` `T`), switched with `Hyper + key`
- Vim-style `HJKL` to move windows, `Hyper + Shift + HJKL` to shift focus
- App launchers: `Hyper + Enter` Ghostty · `Hyper + V` VS Code · `Hyper + E` Zed · `Hyper + C` Claude · `Hyper + R` RStudio · `Hyper + Shift + O` Obsidian
- Apps auto-open in their workspace (Obsidian in `A`, editors/RStudio in `D`, messaging in `G`)
- Finder, System Settings, Activity Monitor and VPN clients float by default
- Workspaces `F` `G` `T` are pinned to the external monitor (EV3895), falling back to the LG UltraGear
- Service mode (`Hyper + Shift + M`) to reload config, flatten the tree, or toggle floating

### [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) ![small text](https://img.shields.io/badge/-Keyboard%20Remapping-blue)

- Caps Lock becomes `Ctrl + Option + Cmd` (the Hyper key that drives AeroSpace)
- Right Command becomes `Fn + Ctrl` (a secondary modifier layer)
- `Fn + Ctrl + HJKL` for arrow keys everywhere on macOS
- `Fn + Ctrl + Enter` opens the current folder in Finder
- Both Shifts together toggle real Caps Lock

### [Ghostty](https://github.com/ghostty-org/ghostty) ![small text](https://img.shields.io/badge/-Terminal%20Emulator-blue)

- Launches Nushell as the default shell

### [Nushell](https://www.nushell.sh) ![small text](https://img.shields.io/badge/-Best%20shell%20ever-blue)

- Structured-data shell that replaced zsh and fish
- Wired in as Ghostty's default command

### [Helix](https://github.com/helix-editor/helix) ![small text](https://img.shields.io/badge/-Text%20Editor%20-blue)

- LSPs wired up: basedpyright + ruff (Python), rust-analyzer with clippy, texlab (LaTeX), marksman (Markdown)
- `jj` to Escape in insert mode, `Esc` collapses the selection

