if exists("b:current_syntax")
    finish
endif

let b:current_syntax = "pikkuwiki_search"

" Links
syntax match pwLink "^[~_/[:alnum:]]\+"
highlight link pwLink Identifier


