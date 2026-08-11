# config.nu
#
# Installed by:
# version = "0.114.1"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R

$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.PROMPT_COMMAND = {||
    let dir = ($env.PWD | str replace $env.HOME "~")
    $"(ansi red_bold)($dir)(ansi reset)"
}
$env.PROMPT_INDICATOR = $"(ansi blue) ❯ (ansi reset)"
$env.config.buffer_editor = "hx"
$env.config.show_banner = false
$env.config.color_config = {
    shape_internalcall: white_bold
    shape_external: white_bold
    shape_externalarg: white_bold
    shape_string: white_bold
    shape_flag: white_bold
    shape_variable: white_bold
    shape_garbage: white_bold
}
$env.config.completions = {
    case_sensitive: false   
    quick: true             
    partial: true           
    algorithm: "fuzzy"      
    sort: "smart"           
    use_ls_colors: true     
    external: {
        enable: false       
        max_results: 100
  }
}
$env.config.history.file_format = "sqlite"
$env.PROMPT_COMMAND_RIGHT = {||
    let git_check = (do { git rev-parse --is-inside-work-tree } | complete)
    if $git_check.exit_code != 0 {
        return ""
}
    let branch = (do { git branch --show-current } | complete | get stdout |str trim)
    let status = (do { git status --porcelain } | complete | get stdout | str trim)
    let is_dirty = ($status != "")
    let color = if $is_dirty { "yellow_bold" } else { "green_bold" }
    let symbol = if $is_dirty { "x" } else { "✓" }
    $"(ansi $color) ($branch) ($symbol)(ansi reset)"
}

source ~/.zoxide.nu
