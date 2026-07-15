function fish_prompt
    set -l last_status $status

    set_color magenta
    echo -n (prompt_pwd)

    echo -n (fish_git_prompt)

    if test $last_status -eq 0
        set_color green
    else
        set_color red
    end
    echo -n ' > '
    set_color yellow
end
