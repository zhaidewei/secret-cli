# Bash completion for the `secret` CLI. Completes subcommands; for
# get/update/rm it completes key names from `secret list`.
# bash has no arrow-key menu — Tab cycles / double-Tab lists candidates.
_secret() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=($(compgen -W "list get add update rm" -- "$cur"))
  elif [[ ${COMP_WORDS[1]} =~ ^(get|update|rm|delete)$ && $COMP_CWORD -eq 2 ]]; then
    COMPREPLY=($(compgen -W "$(secret list 2>/dev/null)" -- "$cur"))
  fi
}
complete -F _secret secret
