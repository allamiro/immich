#!/usr/bin/env bash
# Image tag rules and small helpers shared by the fork build scripts. Source it; it defines
# patterns and functions only.
#
# FORK_TAG_PATTERN          the only release-like name this fork publishes: vX.Y.Z[-pre]-fork.N
# looks_like_release NAME   true for names an upstream release or channel could carry, compared
#                           case-insensitively: anything starting with v and a digit (v3, V3.4.1,
#                           v3.4.1-rc.1) or with digits, a dot and a digit (3.4, 3.4.1). Short commit
#                           tags (7 hex digits, no dot) do not match.
# is_reserved_tag NAME      true for channel names, compared case-insensitively: latest, edge,
#                           main, master, release, stable, nightly.
# PROMOTED_TAGS             the channel tags this fork moves: latest, edge, main.
# is_foreign_tag NAME       true for a registry tag this fork must never carry: a release-like
#                           name that is not vX.Y.Z[-pre]-fork.N, or a channel name other than
#                           exactly latest, edge or main.
# random_delimiter          a fresh delimiter for multi-line $GITHUB_OUTPUT values.
# retry COMMAND...          runs COMMAND up to RETRY_ATTEMPTS times (default 4), waiting
#                           RETRY_DELAY seconds (default 2) and doubling it after each failure.

# shellcheck disable=SC2034
FORK_TAG_PATTERN='^v([0-9]+\.[0-9]+\.[0-9]+)(-([A-Za-z0-9.]+))?-fork\.([0-9]+)$'
# shellcheck disable=SC2034
PROMOTED_TAGS='latest edge main'

lowercase() {
  tr '[:upper:]' '[:lower:]' <<< "$1"
}

looks_like_release() {
  local name
  name=$(lowercase "$1")
  [[ "$name" =~ ^v[0-9] || "$name" =~ ^[0-9]+\.[0-9] ]]
}

is_reserved_tag() {
  case "$(lowercase "$1")" in
    latest | edge | main | master | release | stable | nightly) return 0 ;;
    *) return 1 ;;
  esac
}

is_foreign_tag() {
  if looks_like_release "$1"; then
    [[ ! "$1" =~ $FORK_TAG_PATTERN ]]
  elif is_reserved_tag "$1"; then
    [[ " ${PROMOTED_TAGS} " != *" $1 "* ]]
  else
    return 1
  fi
}

random_delimiter() {
  printf 'FORK_EOF_%s' "$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
}

retry() {
  local attempt=1 attempts=${RETRY_ATTEMPTS:-4} delay=${RETRY_DELAY:-2}
  until "$@"; do
    if [[ "$attempt" -ge "$attempts" ]]; then
      return 1
    fi
    echo "Attempt ${attempt} of ${attempts} failed: $*; retrying in ${delay}s." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
