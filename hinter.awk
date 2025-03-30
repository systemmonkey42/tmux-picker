@include "join" # gawk 4.1 was released in 2013

BEGIN {
	n_matches = 0;

	highlight_patterns = ENVIRON["PICKER_PATTERNS"]
	num_hints_needed = ENVIRON["NUM_HINTS_NEEDED"]
	blacklist = "(^\x1b\\[[0-9;]{1,9}m|^|[[:space:]:<>)(&#'\"])"ENVIRON["PICKER_BLACKLIST_PATTERNS"]"$"

	hint_format = ENVIRON["PICKER_HINT_FORMAT"]
	hint_prefix_format = ENVIRON["PICKER_HINT_PREFIX_FORMAT"]
	hint_format_nocolor = ENVIRON["PICKER_HINT_FORMAT_NOCOLOR"]
	hint_format_len = length(sprintf(hint_format_nocolor, ""))
	highlight_format = ENVIRON["PICKER_HIGHLIGHT_FORMAT"]
	compound_format = hint_prefix_format hint_format highlight_format

	gen_hints()

	hint_lookup = ""
}

# Trivial "join()", all elements, no separators
function concat(a) {
	str=""
	for(i=0;i<length(a);i++) {
		str=str a[i]
	}
	return str
}

# Map/Unmap ansi code positions
# The map_code() and accompanying unmap() functions are used to
# 1. Save the input to `line`
# 2. Create a copy with all ansi color codes stripped in `cline`
# 3. Provide a mapping table to convert an offset into `cline` back
#    into an offset into `line`.
# After match()'ing a string in `cline`, the RSTART and RLENGTH values
# are unmapp()ed, so the original text can be extracted from `line`.

function map_code(l) {
	delete fmap
	delete omap

	# Save input line
	line = l

	# Create two tables, `f` contained the set of ansi color codes, and `s` containing the plain text.
	patsplit(l,f,/\x1b\[[0-9;]+m/,s)

	# Create a plain copy by concatenating the plain text
	cline = concat(s)

	# Create the mapping table such char cline[x] == line[unmap(x)]
	x = 0
	y = 0
	n = 0
	for(i=0;i<length(s);i++) {
		x += length(f[i])
		y += length(s[i])
		fmap[n] = x
		omap[n] = y
		if( i == 0 || length(s[i]) > 0 ) {
			n++
		}
	}
	# Handle terminator - last value is highest possible index
	fmap[n] = length(l)
}

# Convert m to m`, such that cline[m] == line[m`].
# Note that line[m`] may in fact point to the ansi color code string preceeding the
# matched text.  This is important because leading ansi codes is well handled, while
# trailing ansi codes are less well handled.
function unmap(m) {
	o=0
	for(_m=0;_m < length(omap); _m++) {
		if(m>omap[_m]) {
			o = fmap[_m+1]
		}
	}
	return m+o
}

{
	# Process initial input line
	map_code($0)

	output_line = "";
	post_match = line;
	skipped_prefix = "";
	skipped_prompt = 0;

	# Try to skip shell prompts
	if (match(cline,"^[a-z]+\\.[a-zA-Z0-9_]+ .*[$#] ?")) {
		skipped_prompt=RLENGTH
	}

	# Inserts hints into `output_line` and accumulate hints in `hint_lookup`
	while (match(substr(cline,skipped_prompt+1), highlight_patterns, matches)) {
		# Convert matched text position back to original indicies
		pstart = unmap(RSTART+skipped_prompt)
		pend = unmap(RSTART+RLENGTH+skipped_prompt)
		pre_match = skipped_prefix substr(line, 1, pstart-1);
		post_match = substr(line, pend);
		# The match will be highlighted, and doesn't make sense to include color codes
		# from original line.
		line_match = matches[0]
		#line_match = substr(line,pstart,pend-pstart)

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

			if (substr(hint,1,length(prefix)) == prefix) {
				hint_len = length(hint) + hint_format_len;
				line_match = substr(line_match, hint_len + 1, length(line_match) - hint_len);
				hint_prefix = substr(hint,1,length(prefix))
				hint_suffix = substr(hint,length(prefix)+1)
				line_match = sprintf(compound_format, hint_prefix,hint_suffix, line_match);

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
		} else {
			skipped_prefix = pre_match line_match; # we need it only to fix colors
		}
		# Prepare to keep processing remaining text
		map_code(post_match);
	}

	printf "\n%s", (output_line skipped_prefix post_match)
}

END {
	print hint_lookup | "cat 1>&3"
}
