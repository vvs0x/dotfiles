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

# config.nu

$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.config.buffer_editor = "hx"
$env.config.show_banner = false
$env.config.history.file_format = "sqlite"

# Prompt
$env.PROMPT_COMMAND = {||
    let dir = ($env.PWD | str replace $env.HOME "~")
    $"(ansi attr_bold)($dir)(ansi reset)"
}
$env.PROMPT_INDICATOR = $"(ansi dark_gray) ❯ (ansi reset)"

# Git status on the right: branch, ahead/behind, * when dirty
$env.PROMPT_COMMAND_RIGHT = {||
    let res = (do { ^git status --porcelain=v2 --branch } | complete)
    if $res.exit_code != 0 { return "" }
    let lines = ($res.stdout | lines)

    let head = ($lines | where {|l| $l | str starts-with "# branch.head " } | str replace "# branch.head " "" | get 0? | default "")
    let oid = ($lines | where {|l| $l | str starts-with "# branch.oid " } | str replace "# branch.oid " "" | get 0? | default "")
    let ab = ($lines | where {|l| $l | str starts-with "# branch.ab " } | str replace "# branch.ab " "" | get 0? | default "+0 -0" | split row " ")
    let ahead = ($ab.0 | str replace "+" "" | into int)
    let behind = ($ab.1 | str replace "-" "" | into int)
    let dirty = ($lines | where {|l| not ($l | str starts-with "#") } | is-not-empty)

    let name = if $head == "(detached)" { $oid | str substring 0..6 } else { $head }
    let marks = [
        (if $ahead > 0 { $"↑($ahead)" })
        (if $behind > 0 { $"↓($behind)" })
        (if $dirty { "*" })
    ] | compact

    $"(ansi dark_gray)([$name ...$marks] | str join ' ')(ansi reset)"
}

# Colours: mostly default, bold commands, dim strings and chrome
$env.config.color_config = {
    shape_internalcall: { attr: b }
    shape_external: { attr: b }
    shape_externalarg: default
    shape_flag: default
    shape_variable: default
    shape_string: dark_gray
    shape_garbage: { attr: u }
    header: { attr: b }
    separator: dark_gray
    row_index: dark_gray
    hints: dark_gray
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

# Git aliases
def gc [msg: string] { git commit -m $msg }
alias gs = git status
alias gph = git push
alias gpl = git pull

source ~/.zoxide.nu
source ~/.config/nushell/sing-box.nu
