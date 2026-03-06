#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

pass_count=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
  pass_count=$((pass_count + 1))
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    fail "Expected '$needle' in $file"
  fi
}

test_help_docstring() {
  local out="$TMPDIR/help.txt"
  set +e
  "$ROOT/make_template.sh" --help >"$out" 2>&1
  local rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || fail "--help should exit 1, got $rc"
  assert_contains "$out" "Usage:"
  assert_contains "$out" "--non-interactive"
  assert_contains "$out" "--exit-code-map"
  pass "help docstring includes key options"
}

test_noninteractive_generation() {
  local out_script="$TMPDIR/generated.sh"
  "$ROOT/make_template.sh" "$out_script" \
    --non-interactive \
    --force \
    --usage-string='input [--flag]' \
    --arg-explanations='input:Input path;[--flag]:Toggle mode' \
    --description='Generated in test.' \
    --exit-code-map='0:success;1:failure' >/dev/null 2>&1

  [[ -f "$out_script" ]] || fail "Expected generated script file"
  assert_contains "$out_script" "# Generated in test."
  assert_contains "$out_script" "parse_args \"input [--flag]\" \"\$@\""
  assert_contains "$out_script" "#  - 1: failure"
  pass "noninteractive generation"
}

test_sbatch_noninteractive_requires_job_name() {
  local out_script="$TMPDIR/sbatch_missing.sh"
  local out="$TMPDIR/sbatch_missing.out"
  set +e
  "$ROOT/make_template.sh" "$out_script" \
    --sbatch \
    --non-interactive \
    --description='x' >"$out" 2>&1
  local rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || fail "Expected missing job name to fail with rc=1, got $rc"
  assert_contains "$out" "Missing --slurm-job-name"
  pass "sbatch noninteractive job-name validation"
}

test_parse_args_allows_empty_positional() {
  local out="$TMPDIR/parse_empty.out"
  bash -c ". \"$ROOT/config/utils.sh\"; parse_args 'first second' '' 'x'; printf 'first=<%s> second=<%s>\n' \"\$first\" \"\$second\"" >"$out"
  assert_contains "$out" "first=<> second=<x>"
  pass "parse_args accepts empty positional args"
}

main() {
  test_help_docstring
  test_noninteractive_generation
  test_sbatch_noninteractive_requires_job_name
  test_parse_args_allows_empty_positional
  echo "All tests passed: $pass_count"
}

main "$@"
