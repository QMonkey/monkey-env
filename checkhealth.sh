#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-env dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
#
# monkey-env is the meta-installer: it fetches and runs the other repos'
# installers. So this check asks only about the two tools the chain itself
# cannot work without. Everything else belongs elsewhere, on purpose:
#   - the component list, its flags and its ordering live in install.sh and are
#     NOT restated here (a second copy would drift the day a component is
#     added, and probing each repo's URL would make an offline host look sick);
#   - version floors belong to each component's own checkhealth.sh, which this
#     chain runs per component — the meta-installer has no version of its own;
#   - config links belong to the component that creates them; monkey-env owns
#     no config file, so there is no CONFIG_LINKS section here;
#   - sudo is probed by the framework's own stage (lib/sudo.sh);
#   - no RECOMMENDED_CHECKS/OPTIONAL_CHECKS either: nothing else is a
#     prerequisite of the chain, and both walkers return on an absent list
#     (`[ ${#…[@]} -gt 0 ] || return 0`), so declaring nothing IS the statement.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	printf '%s\n' "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	printf '%s\n' "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-env

# ──────────────────────── required ────────────────────────
# The same two prerequisites install.sh fails fast on (it fetches each
# component installer with curl and clones each repository with git), declared
# here so they can be answered BEFORE a run instead of midway through the
# chain — and installed by `checkhealth.sh --install`, which is what a bare
# host needs first.
REQUIRED_CHECKS=(
	"@header|Required tools"
	"git|bin|git (clones every component repository)"
	"curl|bin|curl (fetches every component installer)"
)

checkhealth_main "$@"
