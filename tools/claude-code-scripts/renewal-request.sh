# shellcheck shell=bash
# The renewal request beside a checkout's work record: stop-continue writes
# it, herdr-renew arms it with an attempt, compact-resume confirms it.
#   {handoff, session_id, pane, state: requested | compacted, attempt?}
# Sourced only by absolute path from the sourcing script's own directory,
# never through PATH: herdr-renew runs outside the sandbox.

# Prints the request's path for the work record at $1.
renewal_file() {
  echo "$(dirname "$1")/renewal"
}

# Prints a request for handoff $1, session $2 and pane $3, armed with
# attempt $4 when given.
renewal_request() {
  # shellcheck disable=SC2016 # jq variables, not shell
  jq -n --arg h "$1" --arg s "$2" --arg p "$3" --arg a "${4:-}" \
    '{handoff: $h, session_id: $s, pane: $p, state: "requested"} + if $a == "" then {} else {attempt: $a} end'
}
