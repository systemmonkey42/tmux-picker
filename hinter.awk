@include "join" # gawk 4.1 was released in 2013

BEGIN {
    n_matches = 0;

    highlight_patterns = ENVIRON["PICKER_PATTERNS"]
    num_hints_needed = ENVIRON["NUM_HINTS_NEEDED"]
    blacklist = "(^\x1b\\[[0-9;]{1,9}m|^|[[:space:]:<>)(&#'\"])"ENVIRON["PICKER_BLACKLIST_PATTERNS"]"$"

    hint_format = ENVIRON["PICKER_HINT_FORMAT"]
    hint_format_nocolor = ENVIRON["PICKER_HINT_FORMAT_NOCOLOR"]
    hint_format_len = length(sprintf(hint_format_nocolor, ""))
    highlight_format = ENVIRON["PICKER_HIGHLIGHT_FORMAT"]
    compound_format = hint_format highlight_format

	gen_hints()

    hint_lookup = ""
}

{
    line = $0;
    output_line = "";
    post_match = line;
    skipped_prefix = "";

    # Inserts hints into `output_line` and accumulate hints in `hint_lookup`
    while (match(line, highlight_patterns, matches)) {
        pre_match = skipped_prefix substr(line, 1, RSTART - 1);
        post_match = substr(line, RSTART + RLENGTH);
        line_match = matches[0]

        if (line_match !~ blacklist) {
            # All sub-patterns start with a prefix group (sometimes empty) that should not be highlighted, e.g.
            #     ((prefix_a)(item_a))|((prefix_b)(item_a))
            # So matches array is looks like: 
            #    ||||prefix_b item_b|prefix_b|item_b|
            #    or    
            #    |prefix_a item_a|prefix_a|item_a||||
            # Unfortunately, we don't know the index of first matching group.
            num_groups = length(matches) / 3; # array contains: idx, idx-start, idx-length for each group
            for (i = 1; i <= num_groups; i++) {
                if (matches[i] != "") {
                    line_match = substr(line_match, 1 + matches[++i, "length"])
                    pre_match = pre_match matches[i]
                    break;
                }
            }

            hint = hint_by_match[line_match]
            if (!hint) {
                hint = HINTS[++n_matches]
                hint_by_match[line_match] = hint
                hint_lookup = hint_lookup hint ":" line_match "\n"
            }

            hint_len = length(hint) + hint_format_len;
            line_match = substr(line_match, hint_len + 1, length(line_match) - hint_len);
            line_match = sprintf(compound_format, hint, line_match);

            # Fix colors broken by the hints highlighting.
            # This is mostly needed to keep prompts intact, so fix first ~500 chars only
            if (length(output_line) < 500) { 
                num_colors = split(pre_match, arr, /\x1b\[[0-9;]{1,9}m/, colors); 
                post_match = join(colors, 1, 1 + num_colors, SUBSEP) post_match;
            }

            output_line = output_line pre_match line_match;
            skipped_prefix = "";
        } else {
            skipped_prefix = pre_match line_match; # we need it only to fix colors
        }
        line = post_match;
    }

    printf "\n%s", (output_line skipped_prefix post_match)
}

END {
    print hint_lookup | "cat 1>&3"
}
