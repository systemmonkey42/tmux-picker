#!/usr/bin/env bash

CURRENT_DIR="$(readlink -e "${BASH_SOURCE[0]%/*}")"

current_pane_id=$1
picker_pane_id=$2
last_pane_id=$3
picker_window_id=$4
pane_input_temp=$5

match_lookup_table="$(mktemp)"

# exporting it so they can be properly deleted inside handle_exit trap
export match_lookup_table

function lookup_match() {
    local input="$1"

	sed -n -e "s/^${input,,}://p;T" -e q "$match_lookup_table"
}

function get_pane_contents() {
    cat "$pane_input_temp"
}

function extract_hints() {
	local prefix="$1"
    clear
    export NUM_HINTS_NEEDED=
    NUM_HINTS_NEEDED="$(get_pane_contents | gawk -f "$CURRENT_DIR/counter.awk")"
    get_pane_contents | gawk -f "$CURRENT_DIR/gen_hints.awk" -f "$CURRENT_DIR/hinter.awk" prefix="${prefix}" 3> "$match_lookup_table"
}

function show_hints_again() {
    local picker_pane_id="$1"
	local hint_prefix="$2"

    tmux swap-pane -t "$current_pane_id" -s "$picker_pane_id" -Z
    extract_hints "${hint_prefix}"
    tmux swap-pane -s "$current_pane_id" -t "$picker_pane_id" -Z
}

function show_hints_and_swap() {
    current_pane_id="$1"
    picker_pane_id="$2"

    extract_hints
    tmux swap-pane -s "$current_pane_id" -t "$picker_pane_id" -Z
}


BACKSPACE=$'\177'

input=''
result=''

function is_pane_zoomed() {
    local pane_id=$1

    tmux list-panes \
        -F "#{pane_id}:#{?pane_active,active,nope}:#{?window_zoomed_flag,zoomed,nope}" \
        | grep -c "^${pane_id}:active:zoomed$"
}

function pane_in_mode() {
	local pane_id="$1"

	IFS=: read -r mode cmd < <(tmux display -t "${pane_id}" -p '#{pane_in_mode}:#{pane_current_command}')
	[[ "${mode}" -ne 0 ]] || [[ "${cmd}" != "bash" ]]
}

function revert_to_original_pane() {
    tmux swap-pane -t "$current_pane_id" -s "$picker_pane_id" -Z

	if (( pane_was_zoomed )); then
		:
	elif [[ -n "$last_pane_id" ]]; then
		tmux select-pane -t "$last_pane_id"
        tmux select-pane -t "$current_pane_id"
    fi
}

function handle_exit() {
    rm -rf "$pane_input_temp" "$match_lookup_table"
    revert_to_original_pane

    if [[ -n "$result" ]]; then
        run_picker_copy_command "$result" "$input"
    fi

    tmux kill-window -t "$picker_window_id"
}

function is_valid_choice() {
	local input="$1"

	! sed -n -e "/^${input,,}[^:]*:/q1" "$match_lookup_table"
}

function is_valid_input() {
    local input=$1
    local is_valid=1

    if [[ $input == "" ]] || [[ $input == "<ESC>" ]]; then
        is_valid=1
    else
        for (( i=0; i<${#input}; i++ )); do
            char=${input:$i:1}

            if [[ ! "$char" =~ ^[a-zA-Z]$ ]]; then
                is_valid=0
                break
            fi
        done
    fi

    echo $is_valid
}

function hide_cursor() {
    tput civis
}

trap "handle_exit" EXIT

# shellcheck disable=SC2153
export PICKER_PATTERNS="$PICKER_PATTERNS1"
export PICKER_BLACKLIST_PATTERNS="$PICKER_BLACKLIST_PATTERNS"

pane_was_zoomed=$(is_pane_zoomed "$current_pane_id")
show_hints_and_swap "$current_pane_id" "$picker_pane_id"

hide_cursor
input=''

function run_picker_copy_command() {
    local result="$1"
	local hint="$2"

	if [[ "${hint}" != "${hint,,}" ]] && [[ -n "$PICKER_COPY_COMMAND_UPPERCASE" ]]; then
        command_to_run="$PICKER_COPY_COMMAND_UPPERCASE"
	elif pane_in_mode "${current_pane_id}" && [[ -n "${PICKER_ALT_COPY_COMMAND}" ]]; then
        command_to_run="$PICKER_ALT_COPY_COMMAND"
    elif [[ -n "$PICKER_COPY_COMMAND" ]]; then
        command_to_run="$PICKER_COPY_COMMAND"
    fi

    if [[ -n "$command_to_run" ]]; then
        tmux run-shell -b "printf '%s' '$result' | $command_to_run"
    fi
}

while read -rsn1 char; do
    if [[ $char == "$BACKSPACE" ]]; then
        input=""
		show_hints_again "$picker_pane_id" "$input"
		continue
    fi

    # Escape sequence, flush input
    if [[ "$char" == $'\x1b' ]]; then
        read -rsn1 -t 0.1 next_char

        if [[ "$next_char" == "[" ]]; then
            read -rsn1 -t 0.1
            continue
        elif [[ "$next_char" == "" ]]; then
            char="<ESC>"
        else
            continue
        fi

    fi

    if [[ ! $(is_valid_input "$char") == "1" ]]; then
        continue
    fi

	if [[ $char == "$BACKSPACE" ]]; then
		input=""
		continue
	elif [[ $char == "<ESC>" ]]; then
		exit
	elif [[ $char == "" ]]; then
		input=""
		if [ "$PICKER_PATTERNS" == "$PICKER_PATTERNS1" ]; then
			# shellcheck disable=SC2153
			export PICKER_PATTERNS="$PICKER_PATTERNS2";
		else
			export PICKER_PATTERNS="$PICKER_PATTERNS1";
		fi
		show_hints_again "$picker_pane_id" "$input"
		continue
	else
		if is_valid_choice "${input}${char}"; then
			input="${input}${char}"
		fi
	fi

    result=$(lookup_match "$input")

    if [[ -z $result ]]; then
		show_hints_again "$picker_pane_id" "$input"
        continue
    fi

    exit 0
done < /dev/tty
