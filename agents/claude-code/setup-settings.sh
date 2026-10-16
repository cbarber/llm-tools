#!/usr/bin/env bash

# Setup Claude Code settings.local.json for hooks
# Creates it from the template when absent, otherwise three-way merges
# template changes into it while keeping local edits.

set -euo pipefail

SETTINGS=".claude/settings.local.json"
# The template as last applied: the merge base that tells template changes
# apart from local edits.
BASE=".claude/.settings.local.base.json"

if [[ ! -f "$SETTINGS" ]]; then
  mkdir -p .claude
  cp "${SETTINGS_TEMPLATE}" "$SETTINGS"
  cp -f "${SETTINGS_TEMPLATE}" "$BASE"
  echo "Created settings.json with Claude Code hooks (notify)"
  exit 0
fi

# Values are wrapped: [] is absent, [v] is present. Unchanged locally takes
# the template; unchanged in the template keeps local; otherwise objects and
# arrays merge per member and local wins the rest. Array elements match by
# key: hook groups by matcher (missing is ""), hooks by command, anything else
# by value. Hook groups sharing a matcher are first collapsed into one (Claude
# Code runs them alike), so keys are unique and deletions cannot shift pairs.
# Without a base every template member counts as added, so the template only
# fills in what is missing.
# shellcheck disable=SC2016
MERGE='
def key:
  if type == "object" and has("hooks") then {matcher: (.matcher // "")}
  elif type == "object" and has("command") then {command}
  else . end;
def collapse:
  reduce .[] as $g ([];
    if ($g | type) == "object" and ($g | has("hooks")) then
      (map(if type == "object" and has("hooks") then .matcher // "" else null end)
       | index($g.matcher // "")) as $i
      | if $i == null then . + [$g] else .[$i].hooks += $g.hooks end
    else . + [$g] end);
def norm:
  if type == "object" and (.hooks | type) == "object" then
    .hooks |= map_values(if type == "array" then collapse else . end)
  else . end;
def field($v; $k): if $v | has($k) then [$v[$k]] else [] end;
def pick($a; $k): [$a[] | select(key == $k)][:1];
def m3($b; $t; $o):
  if $o == $b then $t
  elif $t == $b then $o
  elif ($o | length) == 0 or ($t | length) == 0 then $o
  elif ($o[0] | type) == "object" and ($t[0] | type) == "object" then
    ($b[0] | if type == "object" then . else {} end) as $bv
    | ($o[0] | keys_unsorted)
      + [$t[0] | keys_unsorted[] | select(. as $k | $o[0] | has($k) | not)]
    | [reduce .[] as $k ({};
        m3(field($bv; $k); field($t[0]; $k); field($o[0]; $k)) as $r
        | if $r == [] then . else .[$k] = $r[0] end)]
  elif ($o[0] | type) == "array" and ($t[0] | type) == "array" then
    ($b[0] | if type == "array" then . else [] end) as $bv
    | [[$o[0][] as $e | ($e | key) as $k
        | m3(pick($bv; $k); pick($t[0]; $k); [$e])[]]
       + [$t[0][] | key as $k
          | select(any($o[0][], $bv[]; key == $k) | not)]]
  else $o end;
m3($base | map(norm); $tmpl | map(norm); [norm])[0]
'

if ! jq empty "${SETTINGS_TEMPLATE}" 2>/dev/null; then
  echo "Warning: ${SETTINGS_TEMPLATE} is missing or not valid JSON; template changes not applied" >&2
  exit 0
fi

base_file=/dev/null
if jq empty "$BASE" 2>/dev/null; then
  base_file=$BASE
fi

if ! merged=$(jq --slurpfile tmpl "${SETTINGS_TEMPLATE}" \
  --slurpfile base "$base_file" "$MERGE" "$SETTINGS"); then
  echo "Warning: ${SETTINGS} is not valid JSON; template changes not applied" >&2
  exit 0
fi

settings_changed=true
if [[ "$(jq -S . <<<"$merged")" == "$(jq -S . "$SETTINGS")" ]]; then
  settings_changed=false
fi
if ! $settings_changed && cmp -s "${SETTINGS_TEMPLATE}" "$BASE"; then
  exit 0
fi

# Replace FILE with stdin by rename, keeping FILE's mode: the files are often
# read-only (copied from the Nix store).
replace() {
  local file=$1 tmp
  tmp=$(mktemp "${file}.XXXXXX" 2>/dev/null) || return 1
  cat >"$tmp"
  if [[ -f "$file" ]]; then
    chmod "$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file")" "$tmp"
  fi
  mv "$tmp" "$file"
}

if $settings_changed && ! printf '%s\n' "$merged" | replace "$SETTINGS"; then
  echo "Warning: ${SETTINGS} is not writable; template changes not applied" >&2
  exit 0
fi
# Record the base only after the merge it describes is in place.
if ! replace "$BASE" <"${SETTINGS_TEMPLATE}"; then
  echo "Warning: ${BASE} is not writable; template changes may reapply" >&2
  exit 0
fi

if $settings_changed; then
  echo "Updated ${SETTINGS} from template"
fi
