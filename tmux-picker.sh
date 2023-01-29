#!/usr/bin/env bash
# shfmt:

CURRENT_DIR="$(readlink -e "${BASH_SOURCE[0]%/*}")"

function init_picker_pane() {
    local picker_ids=
    local picker_pane_id=
    local picker_window_id=
    picker_ids=$(tmux new-window -F "#{pane_id}:#{window_id}" -P -d -n "[picker]" "/bin/sh")
    picker_pane_id=$(echo "$picker_ids" | cut -f1 -d:)
    picker_window_id=$(echo "$picker_ids" | cut -f2 -d:)

    if [[ -n "$last_pane_id" ]]; then # to save precious milliseconds;)
        local current_size=
        local current_width=
        local current_height=
        local current_window_size=
        local current_window_width=
        local current_window_height=
        current_size=$(tmux list-panes -F "#{pane_width}:#{pane_height}:#{?pane_active,active,nope}" | grep active)
        current_width=$(echo "$current_size" | cut -f1 -d:)
        current_height=$(echo "$current_size" | cut -f2 -d:)

        current_window_size=$(tmux list-windows -F "#{window_width}:#{window_height}:#{?window_active,active,nope}" | grep active)
        current_window_width=$(echo "$current_window_size" | cut -f1 -d:)
        current_window_height=$(echo "$current_window_size" | cut -f2 -d:)

        # this is needed to handle wrapped lines inside split windows:
        tmux split-window -d -t "$picker_pane_id" -h -l "$((current_window_width - current_width - 1))" '/bin/sh'
        tmux split-window -d -t "$picker_pane_id" -l "$((current_window_height - current_height - 1))" '/bin/sh'
    fi

    echo "$picker_pane_id:$picker_window_id"
}

function capture_pane() {
    local pane_id=$1
    local out_path=$2
    local pane_info=
    pane_info=$(tmux list-panes -s -F "#{pane_id}:#{pane_height}:#{scroll_position}:#{?pane_in_mode,1,0}" | grep "^$pane_id")

    local pane_height=
    local pane_scroll_position=
    local pane_in_copy_mode=

    IFS=: read -r _ pane_height pane_scroll_position pane_in_copy_mode <<<"${pane_info}"

    local start_capture=""

    if [[ "$pane_in_copy_mode" == "1" ]]; then
        start_capture=$((-pane_scroll_position))
        end_capture=$((pane_height - pane_scroll_position - 1))
    else
        start_capture=0
        end_capture="-"
    fi

    tmux capture-pane -e -J -p -t "$pane_id" -E "$end_capture" -S "$start_capture" >"$out_path"
}

function pane_exec() {
    local pane_id=$1
    local pane_command=$2

    tmux send-keys -t "$pane_id" " $pane_command"
    tmux send-keys -t "$pane_id" Enter
}

function prompt_picker_for_pane() {
    local current_pane_id=$1
    local last_pane_id=$2

    local tmp_path=
    local picker_pane_id=
    local picker_window_id=
    local picker_init_data=

    picker_init_data="$(init_picker_pane "$last_pane_id")"
    IFS=: read -r picker_pane_id picker_window_id <<<"${picker_init_data}"

    tmp_path=$(mktemp)

    capture_pane "$current_pane_id" "$tmp_path"
    pane_exec "$picker_pane_id" "$CURRENT_DIR/hint_mode.sh \"$current_pane_id\" \"$picker_pane_id\" \"$last_pane_id\" \"$picker_window_id\" $tmp_path"

    echo "$picker_pane_id"
}

function already_open() {
    read -r _ < <(tmux list-windows -f "#{==:#{window_name},[picker]}" -F1 2>/dev/null)
}

already_open && exit 0

last_pane_id=$(tmux display -pt':.{last}' '#{pane_id}' 2>/dev/null)
current_pane_id=$(tmux list-panes -F "#{pane_id}:#{?pane_active,active,nope}" | grep active | cut -d: -f1)
picker_pane_id=$(prompt_picker_for_pane "$current_pane_id" "$last_pane_id")
