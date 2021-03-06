#!/bin/sh

# Read env variables
[ -z "$PIKKUWIKI_DIR" ] && PIKKUWIKI_DIR="$HOME/pikkuwiki"
[ -z "$EDITOR" ] && EDITOR=vi
[ -z "$PAGER" ] && PAGER=cat
[ -z "$PW_DEFAULT_PAGE" ] && PW_DEFAULT_PAGE="index"
[ -z "$PW_FILE_EXT" ] && PW_FILE_EXT="txt"

# Enable "strict" mode
set -eu

# Pattern for recognizing links to other files
LINK_PATTERN='~\S\+'

grep_links() {
    grep -ow "$LINK_PATTERN"
}

filename_to_link() {
    local link
    link=${1#$PIKKUWIKI_DIR}
    link=${link#/}
    link=${link%.$PW_FILE_EXT}
    echo "$link"
}

starts_with() {
    local str="$1"
    local prefix="$2"
    local prefix_len=${#prefix}
    [ "$(echo "$str" | cut -c"$prefix_len")" = "$prefix" ]
}

resolve_link() {
    local context=${1#$PIKKUWIKI_DIR}
    context="/${context#/}"
    context=${context%/*}
    local link=${2#\~}
    link=${link%.$PW_FILE_EXT}
    link=${link:-$PW_DEFAULT_PAGE}

    if starts_with "$link" "/" || [ "$context" = "/" ]; then
        context="$PIKKUWIKI_DIR"
    else
        context="$PIKKUWIKI_DIR$context"
    fi

    link=${link#/}

    echo "$context/$link.$PW_FILE_EXT"
}

resolve_links() {
    while read line; do
        resolve_link "$1" "$line"
    done
}

find_links_from_file() {
    grep_links < "$1" | grep "$2" | resolve_links "$filename"
}

find_links() {
    local filename="${1:-}"
    local pattern=${2:-}

    if [ ! -f "$filename" ]; then
        filename=$(resolve_link "" "$filename")
    fi
    
    if [ ! -f "$filename" ]; then
        echo "Could not find a file for '$1'!" 1>&2
    fi

    find_links_from_file "$filename" "$pattern"
}

find_pages() {
    if [ "$1" ]; then
        find "$PIKKUWIKI_DIR" -iname "*.$PW_FILE_EXT" -iname "*$1*"
    else
        find "$PIKKUWIKI_DIR" -iname "*.$PW_FILE_EXT"
    fi
}

do_to_lines() {
    if [ ! "$1" ]; then
        cat
    fi
    while read line; do
        $1 "$line"
    done
}

format_links() {
    local format=${1:-}
    local formatter=""
    local after_formatter=""

    case "$format" in
        h|head|header) formatter="formatter_header" ;;
        l|link)        formatter="filename_to_link" ;;
        ""|f|file) ;;
        p|pretty)
            formatter="formatter_pretty"
            after_formatter="after_formatter_pretty"
            ;;
        space)
            formatter="filename_to_link"
            after_formatter="lines_to_words"
            ;;
        *)
            echo "Unknown formatter '$format'!" 1>&2
            return 1
            ;;
    esac

    if [ "$after_formatter" ]; then
        do_to_lines "$formatter" | $after_formatter
    else
        do_to_lines "$formatter"
    fi
}

formatter_header() {
    local filename=${1:-}
    local heading="[No file]"
    [ -f "$filename" ] && heading=$(head -n1 "$filename")
    echo "$heading"
}

formatter_pretty() {
    local filename=${1:-}
    local link=$(filename_to_link "$filename")
    printf "%s:	%s\n" "$link" "$(formatter_header "$filename")"
}

after_formatter_pretty() {
    column -t -s"	"
}

lines_to_words() {
    tr '\n' ' '
}

find_and_format_pages() {
    local pattern=""
    local format=""
    while getopts "p:F:" flag; do
        case "$flag" in
            p) pattern=${OPTARG:-} ;;
            F) format=${OPTARG:-} ;;
        esac
    done
    find_pages "$pattern" | format_links "$format" | sort -u
}

show_and_format_links() {
    local pattern=""
    local format=""
    local link=""
    while getopts "l:p:F:" flag; do
        case "$flag" in
            l) link=${OPTARG:-} ;;
            p) pattern=${OPTARG:-} ;;
            F) format=${OPTARG:-} ;;
        esac
    done
    find_links "$link" "$pattern" | format_links "$format" | sort -u
}

open_link() {
    $EDITOR "$(resolve_link "" "$1")"
}

view_link() {
    $PAGER "$(resolve_link "" "$1")"
}

init_pikkuwiki() {
    local firstpage="$PIKKUWIKI_DIR/$PW_DEFAULT_PAGE.$PW_FILE_EXT"
    if [ ! -d "$PIKKUWIKI_DIR" ]; then
        mkdir -p "$PIKKUWIKI_DIR"
    fi
    if [ ! -f "$firstpage" ]; then
        cat <<EOF > "$firstpage"
Homepage
========

Hi, this is your first pikkuwiki page.
Add more .$PW_FILE_EXT files to this directory.
EOF
        echo "pikkuwiki initialized successfully!" 1>&2
        echo "your first page can be found from: $firstpage" 1>&2
    else
        echo "pikkuwiki is already initialized!" 1>&2
    fi
}

# Main program
run_pikkuwiki() {
    local cmd=${1:-}

    if [ ! "$cmd" ]; then
        unknown_command
        exit $?
    fi

    shift
    case "$cmd" in
        init)       init_pikkuwiki ;;
        v|view)     view_link "${1:-}" ;;
        o|open)     open_link "${1:-}" ;;
        f|find)     find_and_format_pages "$@" ;;
        s|show)     show_and_format_links "$@" ;;
        r|resolve)  resolve_link "${1:-}" "${2:-}" ;;
        h|help)     print_fullhelp ;;
        *)          unknown_command "$cmd" ;;
    esac
}

unknown_command() {
    if [ "${1:-}" ]; then
        echo "Unknown command '$1'!" 1>&2
    else
        echo "No command specified!" 1>&2
    fi
    print_minihelp 1>&2
    return 1
}

print_minihelp() {
    cat <<'EOF'

usage: pikkuwiki <command> [arguments]

Commands:
  init        Initialize pikkuwiki. Creates the pikkuwiki directory.

  o, open     Open a given link using EDITOR. If link is empty,
              PW_DEFAULT_PAGE or "index" is opened instead.

  v, view     Open a given link using PAGER. If link is empty,
              PW_DEFAULT_PAGE or "index" is opened instead.

  f, find     Find pages using the given pattern. Outputs the filenames of
              found links unless alternative formatting is provided.

  s, show     Show links from given page. Outputs the filenames of the found
              links unless alternative formatting is provded.

  r, resolve  Resolve filename for given filename and link combination

  h, help     Print full help text

Find arguments:
  -p          RegEx pattern to use for filtering pages.
  -F          Use alternative formatting.

Show arguments:
  -l          link or file to search links from.
  -p          RegEx pattern to use for filtering pages
  -F          Use alternative formatting. See the available formatters below.

Formatters:
  header    first line of the page
  file      file path of the page (default)
  link      link to the page from root
  pretty    the link and the header
  space     links separated by spaces (useful for bash completion list)

EOF
}

print_fullhelp() {
    echo "pikkuwiki - Minimal personal wiki tool"
    print_minihelp
    cat <<'EOF'

Examples
========

Open a page in editor:
  pikkuwiki open '~America/Canada'
  pikkuwiki o Europe/Germany

Find pages:
  pikkuwiki find 'code'
  pikkuwiki f 'eng'

Show all links in a page:
  pikkuwiki show -l Europe/Germany
  pikkuwiki s -l Europe

Show matching links:
  pikkuwiki s -l Europe/Germany -p 'Ber'

Resolve link:
  pikkuwiki resolve Europe Germany
  pikkuwiki r $PIKKUWIKI_DIR/Europe/Germany.txt Berlin


Configuration
=============

Pikkuwiki can be configured through environment variables.

  PIKKUWIKI_DIR         The directory where pages are located.
                        Default: $HOME/pikkuwiki

  EDITOR                The editor that the open command launches.
                        Default: vi

  PAGER                 The viewer that is view command launches.
                        Default: cat

  PW_DEFAULT_PAGE       The default page that is opened if no link
                        is provided for open command.
                        Default: index

  PW_FILE_EXT           The file extension for pages.
                        Default: txt


Link syntax
===========

All links to other pages start with tilde (~).
All pages point to a .txt file by default (case sensitive).
The file extension can be customized by changing the PW_FILE_EXT variable.
The page which the link refers to depends on where the page that is linking.

Absolute links:
  ~/Europe            => $PIKKUWIKI_DIR/Europe.txt
  ~/Europe/Germany    => $PIKKUWIKI_DIR/Europe/Germany.txt

Relative links in '~/Europe' page:
  ~America            => $PIKKUWIKI_DIR/America.txt
  ~America/Canada     => $PIKKUWIKI_DIR/America/Canada.txt

Relative links in '~/Europe/Germany' page:
  ~Berlin             => $PIKKUWIKI_DIR/Europe/Germany/Berlin.txt
  ~Munich             => $PIKKUWIKI_DIR/Europe/Germany/Munich.txt
EOF
}

run_pikkuwiki "$@"
