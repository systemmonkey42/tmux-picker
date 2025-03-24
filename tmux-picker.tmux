#!/usr/bin/env bash
# shfmt:

#
# HELPERS
#

CURRENT_DIR="$(readlink -e "${BASH_SOURCE[0]%/*}")"
TMUX_PRINTER="$CURRENT_DIR/tmux-printer/tmux-printer"

function set_tmux_env() {
    local option_name="$1"
    local final_value="$2"

    tmux setenv -g "$option_name" "$final_value"
}

function process_format() {
    echo -ne "$($TMUX_PRINTER "$1")"
}

function array_join() {
    local IFS="$1"
    shift
    echo "$*"
}

function gen_hint_map() {
    [[ -f "${CURRENT_DIR}/gen_hints.awk" ]] ||
        "${CURRENT_DIR}/gen_hints.py" >"${CURRENT_DIR}/gen_hints.awk"
}

#
# CONFIG
#

# Every pattern have be of form ((A)B) where:
#  - A is part that will not be highlighted (e.g. escape sequence, whitespace)
#  - B is part will be highlighted (can contain subgroups)
#
# Valid examples:
#   (( )([a-z]+))
#   (( )[a-z]+)
#   (( )(http://)[a-z]+)
#   (( )(http://)([a-z]+))
#   (( |^)([a-z]+))
#   (( |^)(([a-z]+)|(bar)))
#   ((( )|(^))|(([a-z]+)|(bar)))
#   (()([0-9]+))
#   (()[0-9]+)
#
# Invalid examples:
#   (([0-9]+))
#   ([0-9]+)
#   [0-9]+

FILE_CHARS="[[:alnum:]_.#$%&+=@~-]"
FILE_PATH_CHARS="[[:alnum:]_.#$%&+=/@~-]"
FILE_START_CHARS="[[:space:]:<>)(&#'\"]"

# default patterns group
PATTERNS_LIST1=(
    "((^|$FILE_START_CHARS)\<$FILE_CHARS{3,})"                                           # anything that looks like file/file path but not too short
    "((^|$FILE_START_CHARS)$FILE_PATH_CHARS*/$FILE_CHARS+)"                              # file paths with /
    "((^|\y|[^\\[])([1-9][0-9]*(\\.[0-9]+)?[kKmMgGtT])\\y)"                              # long numbers
    "((^|\y|[^\\[])[0-9]+\\.[0-9]{3,}|[0-9]{5,})"                                        # long numbers
    "(()[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"                   # UUIDs
    "(()((0x)?(([0-9a-f]{6,15})|([0-9a-f]{32})|([0-9a-f]{40})|([0-9a-f]{64}))))"         # HEX strings (crc/sha/md5)
    "(()(https?://|git@|git://|ssh://|ftp://|file:///)[[:alnum:]?=%/_.:,;~@!#$&)(*+-]*)" # URLs
    "(()[[:digit:]]{1,3}\\.[[:digit:]]{1,3}\\.[[:digit:]]{1,3}\\.[[:digit:]]{1,3})"      # IPv4 adresses
    "(()([[:digit:]a-f]{0,4}:){3,})([[:digit:]a-f]{1,4})"                                # IPv6 addresses
    "(()0x[0-9a-fA-F]+)"                                                                 # hex numbers
)

# alternative patterns group (shown after pressing the SPACE key)
PATTERNS_LIST2=(
    "((^|$FILE_START_CHARS)$FILE_CHARS*/$FILE_CHARS+)"                                   # file paths with /
    "((^|$FILE_START_CHARS)\<$FILE_CHARS{5,})"                                           # anything that looks like file/file path but not too short
    "(()(https?://|git@|git://|ssh://|ftp://|file:///)[[:alnum:]?=%/_.:,;~@!#$&)(*+-]*)" # URLs
)

# items that will not be highlighted
BLACKLIST=(
    "(deleted|modified|renamed|copied|master|mkdir|[Cc]hanges|update|updated|committed|commit|working|discard|directory|staged|add/rm|checkout)"
)

# "-n M-f" for Alt-F without prefix
# "f" for prefix-F
declare -a PICKER_KEY=("-n M-f" "-T copy-mode M-f")

#
# Setup
#

gen_hint_map

set_tmux_env PICKER_PATTERNS1 "$(array_join "|" "${PATTERNS_LIST1[@]}")"
set_tmux_env PICKER_PATTERNS2 "$(array_join "|" "${PATTERNS_LIST2[@]}")"
set_tmux_env PICKER_BLACKLIST_PATTERNS "$(array_join "|" "${BLACKLIST[@]}")"

set_tmux_env PICKER_COPY_COMMAND "tmux load-buffer -w - && tmux paste-buffer"
set_tmux_env PICKER_ALT_COPY_COMMAND "tmux load-buffer -w - && tmux delete-buffer -b register || true"
set_tmux_env PICKER_COPY_COMMAND_UPPERCASE "bash -c 'arg=\$(cat -); tmux split-window -h -c \"#{pane_current_path}\" vim \"\$arg\"'"

#set_tmux_env PICKER_HINT_FORMAT "$(process_format "#[fg=color0,bg=color202,dim,bold]%s")"
#set_tmux_env PICKER_HINT_FORMAT "$(process_format "#[fg=black,bg=red,bold]%s")"
set_tmux_env PICKER_HINT_FORMAT "$(
    tput setaf 252
    tput setab 19
    echo -n '%s'
)"
set_tmux_env PICKER_HINT_PREFIX_FORMAT "$(
    tput setaf 252
    tput setab 88
    echo -n '%s'
)"
set_tmux_env PICKER_HINT_FORMAT_NOCOLOR "%s"

#set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(process_format "#[fg=black,bg=color227,normal]%s")"
set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(process_format "#[fg=black,bg=yellow,bold]%s")"
set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(
    tput setaf 215
    tput setab 235
    echo -n '%s'
    tput sgr0
)"

#
# BIND
#

# shellcheck disable=SC2086
for key in "${PICKER_KEY[@]}"; do
    tmux bind ${key} run-shell "$CURRENT_DIR/tmux-picker.sh"
done
