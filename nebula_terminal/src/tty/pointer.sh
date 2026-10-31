# Native line-editor operations reuse the owned query binding and numeric argument.
# 0=query; 1..4097=move; 4098..8194=range start; 8195..12291=delete to endpoint.
# Readline rejects arguments above 1,000,000, so endpoints travel separately.
__pebrel_pointer_supported() {
    [ "${__pebrel_editor_ready:-0}" = 1 ] || return 1
    local bindings digit
    if [ -n "${BASH_VERSION-}" ]; then
        [[ -o emacs ]] || return 1
        bindings=$(bind -X 2>/dev/null)
        [[ $bindings == *'"\e[45~": "__pebrel_editor_report"'* ]] || return 1
        bindings=$(bind -p 2>/dev/null)
        for digit in 0 1 2 3 4 5 6 7 8 9; do
            [[ $bindings == *'"\e'"$digit"'": digit-argument'* ]] || return 1
        done
    else
        [[ $(bindkey -lL main) == 'bindkey -A emacs main' ]] || return 1
        [[ $(bindkey '\e[45~') == *' __pebrel_editor_report' ]] || return 1
        for digit in 0 1 2 3 4 5 6 7 8 9; do
            [[ $(bindkey "\e$digit") == *' digit-argument' ]] || return 1
        done
    fi
}

__pebrel_pointer_ready_report() {
    unset __pebrel_pointer_line __pebrel_pointer_point __pebrel_pointer_anchor
    if __pebrel_pointer_supported; then
        printf '\033]1337;SetUserVar=pebrel_pointer_ready=%s\007' "$__pebrel_shell_token"
    fi
}

__pebrel_pointer_emit() {
    local encoded
    encoded=$(printf '%s' "$2" | base64 | tr -d '\r\n')
    printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$encoded"
}

__pebrel_pointer_action() {
    local argument=$1 line point owner prefix bytes target first last
    case $argument in ''|*[!0-9]*) return ;; esac
    [ ${#argument} -le 5 ] && [ "$argument" -le 12291 ] || return
    owner=$(printf '%s' "$__pebrel_shell_token" | base64 -d)
    if [ -n "${BASH_VERSION-}" ]; then line=$READLINE_LINE; point=$READLINE_POINT
    else line=$BUFFER; point=$CURSOR; fi
    if [ "$argument" = 0 ]; then
        unset __pebrel_pointer_line __pebrel_pointer_point __pebrel_pointer_anchor
        if ! __pebrel_pointer_supported; then
            __pebrel_pointer_emit pebrel_pointer "$owner"$'\nunsupported'
            return
        fi
        # Store the native editor state, not terminal echo or a keystroke mirror.
        __pebrel_pointer_line=$line
        __pebrel_pointer_point=$point
        __pebrel_pointer_token=$__pebrel_shell_token
        if [ -n "${BASH_VERSION-}" ]; then prefix=${line:0:point}
        elif (( point == 0 )); then prefix=''
        else prefix=${line[1,point]}; fi
        local LC_ALL=C
        bytes=${#prefix}
        if [ ${#line} -gt 4096 ]; then
            unset __pebrel_pointer_line __pebrel_pointer_point
            __pebrel_pointer_emit pebrel_pointer "$owner"$'\nunsupported'
        else
            __pebrel_pointer_emit pebrel_pointer "$owner"$'\nutf8\n'"$bytes"$'\n'"$line"
        fi
        return
    fi
    # Revalidate in the editor callback: host revisions alone cannot catch a
    # native history widget, cursor movement or other input queued in the PTY.
    if [ "${__pebrel_pointer_token-}" != "$__pebrel_shell_token" ] ||
       [ "${__pebrel_pointer_point-}" != "$point" ] ||
       [ "${__pebrel_pointer_line-}" != "$line" ] || ! __pebrel_pointer_supported; then
        unset __pebrel_pointer_line __pebrel_pointer_point __pebrel_pointer_anchor
        __pebrel_pointer_emit pebrel_pointer_status "$owner"$'\nrejected'
        return
    fi
    target=$(( (argument - 1) % 4097 ))
    [ "$target" -le ${#line} ] || return
    if [ "$argument" -le 4097 ]; then
        if [ -n "${BASH_VERSION-}" ]; then READLINE_POINT=$target
        else CURSOR=$target; fi
        __pebrel_pointer_point=$target
    elif [ "$argument" -le 8194 ]; then
        __pebrel_pointer_anchor=$target
    elif [ -n "${__pebrel_pointer_anchor-}" ]; then
        first=$__pebrel_pointer_anchor; last=$target
        if [ "$first" -gt "$last" ]; then first=$target; last=$__pebrel_pointer_anchor; fi
        if [ -n "${BASH_VERSION-}" ]; then
            READLINE_LINE=${line:0:first}${line:last}
            READLINE_POINT=$first
        else
            if (( first == 0 )); then prefix=''; else prefix=${line[1,first]}; fi
            BUFFER=$prefix${line[$((last + 1)),-1]}
            CURSOR=$first
        fi
        # One native buffer mutation preserves the line editor's undo record.
        unset __pebrel_pointer_line __pebrel_pointer_point __pebrel_pointer_anchor
    fi
}
