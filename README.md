# nice-bash-scripting
Utilities that make writing bash scripts easier.

## Requirements
- Linux (or similar Unix shell environment)
- `bash` with associative array support
- `python3` (used to compute relative paths in generated scripts)

## Generate A New Script
Run:
```bash
./make_template.sh path/to/new_script.sh
```

Optional:
```bash
./make_template.sh path/to/new_script.sh --sbatch
```

Non-interactive (automation/bots):
```bash
./make_template.sh path/to/new_script.sh \
  --non-interactive \
  --force \
  --usage-string="input [--flag] [--out=<path>]" \
  --arg-explanations="input:Input path;[--flag]:Enable extra mode;[--out=<path>]:Output path" \
  --description="Generate something useful." \
  --exit-code-map="0:success;1:validation failure"
```

For non-interactive sbatch templates, include:
- `--sbatch`
- `--slurm-job-name=<name>` (required)
- optional `--output-file-format=<pattern>`

Useful non-interactive options:
- `--description-file=<path>` as an alternative to `--description`
- `--force` to overwrite an existing destination file without prompting

What the generator asks for:
- Usage string (non-sbatch mode), e.g. `input_file [--force] [--out=<path>]`
- Description (end with two blank lines)
- Exit code meanings
- SBATCH metadata if `--sbatch` is enabled

The generated script includes:
- Header comments (description, arguments, exit codes)
- `config/utils.sh` and `config/config.sh` imports
- Strict mode (`set -euo pipefail`)
- Argument parsing scaffold (non-sbatch mode)

## Argument Parsing (`parse_args`)
`parse_args` lives in `config/utils.sh`.

Usage:
```bash
parse_args "input [--dry-run] [--output=<path>]" "$@"
```

Behavior:
- Positional args become variables by name (`input` in the example).
- Explicit empty positional args are allowed (e.g. `""`).
- Flags are booleans (`dry_run=false` unless passed, then `true`).
- Keyword args default to `EMPTY` unless already defined in environment.
- `-h`/`--help` prints the script header comment as usage text.
- Hyphens in option names are converted to underscores.

## Error Reporting Utilities
Key helpers in `config/utils.sh`:
- `err "message"`: timestamped error output, with call stack when `VERBOSITY > 2`
- `warn "message"`: warning output (`VERBOSITY > 0`)
- `msg "message"`: informational output (`VERBOSITY > 1`)

`VERBOSITY` defaults to `3` and can be set in `config/config.sh` or per script.

## Temporary Variable Scope Helpers
- `using VAR VALUE`: push current value of `VAR` and assign `VALUE`
- `gnisu`: restore the most recently saved variable state

This pattern is useful when temporarily changing shell globals like `IFS` or `COLUMNS`.

## Tests
Run the smoke tests with:
```bash
./tests/run_tests.sh
```
