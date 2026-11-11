# recents.zsh — recent-directory picker for zsh / iTerm2

# Add to the END of ~/.zshrc:
#   source ~/Documents/work-space/open-source/recents/recents.zsh
#
# Keys:  h ← left   j ↓ down   k ↑ up   l → right   (arrow keys work too)
#        enter / space  cd into the selected dir
#        1-9            jump straight to that entry and cd
#        /              search: type to filter, enter keeps the filter,
#                       esc cancels (esc again outside search clears it)
#        q              quit — closes the terminal
#        e / esc        dismiss the picker, stay in the shell
#
# Run `recents` (or `r`) any time to open the picker again.

: ${RECENTS_FILE:=$HOME/.recent_dirs}   # where history is stored
: ${RECENTS_MAX:=30}                    # how many dirs to remember
: ${RECENTS_ON_START:=1}                # show picker when a new shell opens in $HOME
: ${RECENTS_NAME_MAX:=28}               # truncate long dir names in the grid

autoload -Uz add-zsh-hook

# tracking: every cd moves the dir to the top of the list
_recents_track() {
  [[ $PWD == $HOME ]] && return
  local -a dirs
  [[ -r $RECENTS_FILE ]] && dirs=(${(f)"$(<$RECENTS_FILE)"})
  dirs=("$PWD" "${(@)dirs:#$PWD}")
  print -rl -- "${(@)dirs[1,RECENTS_MAX]}" >| $RECENTS_FILE
}
add-zsh-hook chpwd _recents_track

# picker 
# These helpers use dynamically-scoped locals from recents():
# dirs names shown sel cols w query searching lines

# rebuild `shown` (indices into dirs) from the current search query
_recents_filter() {
  local i n
  shown=()
  for (( i = 1; i <= $#dirs; i++ )); do
    n=${dirs[i]:t}
    [[ -z $query || ${(L)n} == *"${(L)query}"* ]] && shown+=($i)
  done
  sel=1
}

_recents_draw() {
  local i r c n out="" rows=$(( ($#shown + cols - 1) / cols ))
  lines=0
  for (( r = 0; r < rows; r++ )); do
    (( r > 0 )) && out+=$'\n'
    out+=$'\r\e[K'
    for (( c = 0; c < cols; c++ )); do
      i=$(( r * cols + c + 1 ))
      (( i > $#shown )) && break
      n=${(r:w:)names[shown[i]]}
      if (( i == sel )); then
        out+=$'\e[1;97;44m'"$n"$'\e[0m  '
      else
        out+=$'\e[1;34m'"$n"$'\e[0m  '
      fi
    done
    (( lines++ ))
  done
  if (( ! $#shown )); then
    out+=$'\r\e[K\e[2m  no matches\e[0m'
    lines=1
  fi

  if (( searching )) || [[ -n $query ]]; then
    out+=$'\n\r\e[K/'"$query"
    (( searching )) && out+=$'\e[7m \e[0m'
    (( lines++ ))
  fi

  # clear whatever is left below from a previous, taller draw
  print -n -- "$out"$'\e[J'
}

# move the cursor back to the first line of the picker
_recents_home() {
  (( lines > 1 )) && print -n $'\e['"$(( lines - 1 ))"'A'
  print -n $'\r'
}

_recents_move() {
  case $1 in
    left)  (( sel > 1 )) && (( sel-- )) ;;
    right) (( sel < $#shown )) && (( sel++ )) ;;
    down)  (( sel + cols <= $#shown )) && (( sel += cols )) ;;
    up)    (( sel - cols >= 1 )) && (( sel -= cols )) ;;
  esac
  return 0
}

recents() {
  local -a dirs names shown
  local d n
  [[ -r $RECENTS_FILE ]] && for d in ${(f)"$(<$RECENTS_FILE)"}; do
    [[ -d $d ]] && dirs+=("$d")
  done
  if (( ! $#dirs )); then
    print "recents: no recent directories yet — cd around and they'll show up here"
    return 1
  fi

  local w=0
  for d in $dirs; do
    n="${d:t}/"
    [[ $d == / ]] && n=/
    (( $#n > RECENTS_NAME_MAX )) && n="${n[1,RECENTS_NAME_MAX-2]}…/"
    names+=("$n")
    (( $#n > w )) && w=$#n
  done

  local cols=$(( COLUMNS / (w + 2) ))
  (( cols < 1 )) && cols=1
  local sel=1 key rest choice="" quit=0 query="" searching=0 lines=0
  _recents_filter

  trap 'print -n $'"'"'\e[?25h'"'"'' EXIT
  print -n $'\e[?25l'
  _recents_draw

  [[ -n $RECENTS_DEBUG ]] && print -r -- "start cols=$cols n=$#dirs COLUMNS=$COLUMNS tty=$TTY" >> ~/.recents_debug.log
  while read -sk1 key; do
    [[ -n $RECENTS_DEBUG ]] && print -r -- "key=${(q+)key} sel=$sel searching=$searching" >> ~/.recents_debug.log
    # arrow keys arrive as ESC [ A/B/C/D; a lone ESC is just "esc"
    if [[ $key == $'\e' ]]; then
      if read -sk2 -t 0.02 rest; then
        case $rest in
          '[D') key=left ;;
          '[C') key=right ;;
          '[B') key=down ;;
          '[A') key=up ;;
          *)    key="" ;;
        esac
      else
        key=esc
      fi
    fi

    if (( searching )); then
      case $key in
        esc) searching=0; query=""; _recents_filter ;;
        $'\n'|$'\r') searching=0 ;;
        $'\x7f'|$'\b')
          if [[ -n $query ]]; then
            query=${query[1,-2]}; _recents_filter
          else
            searching=0
          fi ;;
        left|right|up|down) _recents_move $key ;;
        $'\C-c') break ;;
        [[:print:]]) query+=$key; _recents_filter ;;
      esac
    else
      case $key in
        h|left)  _recents_move left ;;
        l|right) _recents_move right ;;
        j|down)  _recents_move down ;;
        k|up)    _recents_move up ;;
        /) searching=1 ;;
        [1-9]) (( key <= $#shown )) && { choice=$dirs[shown[key]]; break } ;;
        $'\n'|$'\r'|' ') (( $#shown )) && { choice=$dirs[shown[sel]]; break } ;;
        q) quit=1; break ;;
        esc)
          # first esc clears an active filter, the next one closes
          [[ -z $query ]] && break
          query=""; _recents_filter ;;
        e|$'\C-c') break ;;
      esac
    fi
    _recents_home
    _recents_draw
  done

  # wipe the picker so the terminal is left clean
  _recents_home; print -n $'\e[J\e[?25h'
  (( quit )) && exit
  [[ -n $choice ]] && cd -- "$choice"
}
alias r=recents

_recents_startup() {
  add-zsh-hook -d precmd _recents_startup
  [[ $TERM_PROGRAM == iTerm.app && -s $RECENTS_FILE ]] || return
  (( ${#RECENTS_START_DIRS} )) && (( ! ${RECENTS_START_DIRS[(Ie)$PWD]} )) && return
  recents
}

[[ -o interactive && $RECENTS_ON_START == 1 ]] && add-zsh-hook precmd _recents_startup
