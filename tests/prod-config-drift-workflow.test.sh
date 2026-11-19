#!/usr/bin/env bash
#
# Tests for files/github/prod-config-drift.yml: runs the workflow's own `gate`
# and `drift` step scripts (pulled out of the YAML) inside a throwaway repo.
#
# What it checks: the workflow checks out the default branch (that is what it
# compares with and opens the PR against), but the drift script it runs must
# come from the commit the run was started on (github.sha). Otherwise
# `gh workflow run prod-config-drift.yml --ref some-branch` silently runs the
# default branch's old script and a fix on that branch can't be tested.
#
# Run: bash tests/prod-config-drift-workflow.test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT}/files/github/prod-config-drift.yml"
FAILS=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# step_run <id>: print the `run:` script of the step with that id.
step_run() {
  php -r '
    require $argv[1] . "/vendor/autoload.php";
    $wf = Symfony\Component\Yaml\Yaml::parseFile($argv[2]);
    foreach ($wf["jobs"]["drift"]["steps"] as $s) {
      if (($s["id"] ?? null) === $argv[3]) { echo $s["run"]; exit(0); }
    }
    fwrite(STDERR, "no step with id $argv[3]\n"); exit(1);
  ' "${ROOT}" "${WORKFLOW}" "$1"
}

# job_env <name>: print a literal job-level env value from the workflow.
job_env() {
  php -r '
    require $argv[1] . "/vendor/autoload.php";
    $wf = Symfony\Component\Yaml\Yaml::parseFile($argv[2]);
    echo $wf["jobs"]["drift"]["env"][$argv[3]] ?? "";
  ' "${ROOT}" "${WORKFLOW}" "$1"
}

GATE="$(step_run gate)" || { echo "FAIL - workflow has no gate step"; exit 1; }
DRIFT="$(step_run drift)" || { echo "FAIL - workflow has no drift step"; exit 1; }
DRIFT_SCRIPT="$(job_env DRIFT_SCRIPT)"
[ -n "${DRIFT_SCRIPT}" ] || DRIFT_SCRIPT=".ci/scripts/config_split/prod-config-drift.sh"

# fake_script <label>: a stand-in drift script that records who ran.
fake_script() {
  mkdir -p "$(dirname "${DRIFT_SCRIPT}")"
  printf '#!/usr/bin/env bash\necho %s > "${MARKER}"\necho drift=false >> "${GITHUB_OUTPUT}"\n' "$1" > "${DRIFT_SCRIPT}"
}

# new_repo <name> <main-has-script:yes|no>: main + a `feature` branch whose
# drift script differs. Leaves main checked out, like the workflow does.
new_repo() {
  local repo="${WORK}/$1"
  git init -q -b main "${repo}"
  cd "${repo}" || exit 1
  git config user.email t@example.com; git config user.name t
  mkdir -p config/sync && echo "a: 1" > config/sync/a.yml
  if [ "$2" = yes ]; then fake_script main; fi
  git add -A && git commit -qm main
  git checkout -qb feature
  fake_script feature
  git add -A && git commit -qm feature
  FEATURE_SHA="$(git rev-parse HEAD)"
  git checkout -q main
  MAIN_SHA="$(git rev-parse HEAD)"
}

# run_steps <script-ref>: run gate then drift; sets RUN and RAN.
run_steps() {
  export SCRIPT_REF="$1" DRIFT_SCRIPT CONFIG_SYNC_DIR=config/sync
  export MARKER="${WORK}/marker" GITHUB_OUTPUT="${WORK}/gate.out"
  rm -f "${MARKER}" "${GITHUB_OUTPUT}"
  bash -e -c "${GATE}" >/dev/null 2>&1
  RUN="$(sed -n 's/^run=//p' "${GITHUB_OUTPUT}" | tail -n 1)"
  RAN=""
  if [ "${RUN}" = true ]; then
    GITHUB_OUTPUT="${WORK}/drift.out" bash -e -c "${DRIFT}" >/dev/null 2>&1
    RAN="$(cat "${MARKER}" 2>/dev/null)"
  fi
}

# 1. Manual run from a branch: that branch's script runs.
new_repo dispatch yes
run_steps "${FEATURE_SHA}"
[ "${RAN}" = feature ] && pass "dispatch from a branch runs that branch's drift script" \
  || fail "dispatch from a branch runs that branch's drift script (ran: '${RAN:-nothing}')"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] && [ -z "$(git status --porcelain)" ] \
  && pass "default branch stays checked out and clean" \
  || fail "default branch stays checked out and clean ($(git status --porcelain | head -3))"

# 2. Scheduled run (github.sha is the default branch): default script runs.
run_steps "${MAIN_SHA}"
[ "${RAN}" = main ] && pass "scheduled run uses the default branch's drift script" \
  || fail "scheduled run uses the default branch's drift script (ran: '${RAN:-nothing}')"

# 3. Branch installs the script for the first time: gate lets it through.
new_repo firstinstall no
run_steps "${FEATURE_SHA}"
[ "${RUN}" = true ] && [ "${RAN}" = feature ] \
  && pass "script only on the dispatched branch still runs" \
  || fail "script only on the dispatched branch still runs (run=${RUN:-unset}, ran: '${RAN:-nothing}')"

# 4. No script anywhere: gate skips.
run_steps "${MAIN_SHA}"
[ "${RUN}" = false ] && pass "no drift script anywhere skips the run" \
  || fail "no drift script anywhere skips the run (run=${RUN:-unset})"

echo
if [ "${FAILS}" -eq 0 ]; then echo "All tests passed."; else echo "${FAILS} test(s) failed."; exit 1; fi
