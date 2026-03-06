#!/bin/bash
# Create a new script from this project template.
# Usage:
#   make_template.sh new_file [--sbatch] [--force] [--non-interactive]
#                    [--usage-string=<text>] [--description=<text>]
#                    [--description-file=<path>] [--arg-explanations=<text>]
#                    [--exit-code-map=<text>] [--slurm-job-name=<name>]
#                    [--output-file-format=<fmt>]
# 
# Positional arguments:
#  - new_file: destination script path to create.
# 
# Optional flags:
#  - --sbatch: generate an sbatch-style script with SBATCH metadata.
#  - --force: overwrite new_file if it already exists.
#  - --non-interactive: do not prompt; rely entirely on provided options.
# 
# Optional values:
#  - --usage-string: usage spec for parse_args in generated script.
#  - --description: one-line or multi-line description text.
#  - --description-file: read description from this file.
#  - --arg-explanations: "arg:desc;arg2:desc2" for comment header.
#  - --exit-code-map: "0:success;1:failure" for exit code comments.
#  - --slurm-job-name: required with --sbatch --non-interactive.
#  - --output-file-format: optional SBATCH --output format.

base="$(dirname "$(realpath "$0")")" # where this script is
# shellcheck disable=SC1091
. "$base"/config/utils.sh
# shellcheck disable=SC1091
. "$base"/config/config.sh
set -eo pipefail
set +u

read_paragraph_until_double_blank() {
  # Read from stdin until two consecutive blank lines.
  local line
  local blank_count=0
  local -a lines=()

  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      blank_count=$((blank_count + 1))
      if (( blank_count >= 2 )); then
        break
      fi
    else
      blank_count=0
    fi
    lines+=("$line")
  done

  printf '%s\n' "${lines[@]}"
}

normalize_empty_placeholder() {
  local varname="$1"
  if [[ "${!varname}" == "EMPTY" ]]; then
    printf -v "$varname" "%s" ""
  fi
}

parse_description_map() {
  # Parse "arg:description;arg2:description2" into comment bullets.
  local map_spec="$1"
  local result="Arguments:"
  local -a entries=()
  local entry key val

  IFS=';' read -r -a entries <<< "$map_spec"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" != *:* ]]; then
      err "Invalid --arg-explanations entry: $entry (expected arg:description)"
      return 1
    fi
    key="${entry%%:*}"
    val="${entry#*:}"
    result="$result\n$(bullet "$key: $val")"
  done

  printf '%s\n' "$result"
}

parse_exit_codes_map() {
  # Parse "0:success;1:failure" into comment bullets.
  local map_spec="$1"
  local result="Exit codes:"
  local -a entries=()
  local entry key val

  IFS=';' read -r -a entries <<< "$map_spec"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" != *:* ]]; then
      err "Invalid --exit-codes entry: $entry (expected code:meaning)"
      return 1
    fi
    key="${entry%%:*}"
    val="${entry#*:}"
    result="$result\n$(bullet "$key: $val")"
  done

  printf '%s\n' "$result"
}

# Parse arguments
sbatch=false
force=false
non_interactive=false
usage_string=""
description=""
description_file=""
arg_explanations=""
exit_code_map=""
slurm_job_name=""
output_file_format=""
new_file=""

parse_args "new_file [--sbatch] [--force] [--non-interactive] [--usage-string=<text>] [--description=<text>] [--description-file=<path>] [--arg-explanations=<text>] [--exit-code-map=<text>] [--slurm-job-name=<name>] [--output-file-format=<fmt>]" "$@"
explanations=""
arg_parsing_block=""
exit_codes="Exit codes:"

for option_name in usage_string description description_file arg_explanations exit_code_map slurm_job_name output_file_format; do
  normalize_empty_placeholder "$option_name"
done

new_file_dir="$(dirname -- "$new_file")"
if [[ ! -d "$new_file_dir" ]]; then
  err "Target directory does not exist: $new_file_dir"
  exit 1
fi

if [[ -e "$new_file" ]]; then
  if $force; then
    msg "Overwriting existing file: $new_file"
  elif $non_interactive; then
    err "Refusing to overwrite existing file in --non-interactive mode without --force: $new_file"
    exit 1
  else
    read -r -p "$(bd "File exists: $new_file. Overwrite? [y/N]"): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      msg "Aborting without overwriting $new_file."
      exit 1
    fi
  fi
fi

if $non_interactive && [[ -n "$description_file" ]] && [[ -n "$description" ]]; then
  err "Use only one of --description and --description-file."
  exit 1
fi

if ! $sbatch; then
  if ! $non_interactive; then
    read -r -p "$(bd "Enter a usage string") [example: \"arg1 [--flag] [--kw-arg=<val>] arg2\"] [default: \"\"]: " usage_string
    : "${usage_string:=}"
  fi

  if $non_interactive && [[ -n "$arg_explanations" ]]; then
    explanations="$(parse_description_map "$arg_explanations")"
  fi

  # Split the usage string and prompt the developer to explain each variable
  if [[ -n "$usage_string" ]] && [[ -z "$explanations" ]]; then
    explanations="Arguments:"
    read -r -a args <<< "${usage_string}"
    for arg in "${args[@]}"; do
      if $non_interactive; then
        arg_explanation=""
      else
        read -r -p "$(bd "Describe $arg"): " arg_explanation
      fi
      explanations="$explanations\n$(bullet "$arg: $arg_explanation")"
    done
  fi

  arg_parsing_block="# ===================
`                   `# Parse the arguments
`                   `# ===================
`                   `
`                   `parse_args \"$usage_string\" \"\$@\"
"
fi

if [[ -n "$description_file" ]]; then
  if [[ ! -f "$description_file" ]]; then
    err "Description file not found: $description_file"
    exit 1
  fi
  description="$(cat -- "$description_file")"
elif [[ -z "$description" ]] && ! $non_interactive; then
  echo "$(bd "Enter a description") [two blank lines to end]: "  >&2
  description="$(read_paragraph_until_double_blank)"
fi

# Describe the exit codes:
if [[ -n "$exit_code_map" ]]; then
  exit_codes="$(parse_exit_codes_map "$exit_code_map")"
elif ! $non_interactive; then
  i=0
  while (( i >= 0 )); do
    read -r -p "$(bd "Meaning of exit code $i") [leave empty to stop]: " exit_code_meaning
    if [[ -n "$exit_code_meaning" ]]; then
      exit_codes="$exit_codes\n$(bullet "$i: $exit_code_meaning")"
      i=$(( i + 1 ))
    else
      i=-1 # break
    fi
  done
fi

# Default script path command (good outside sbatch)
# shellcheck disable=SC2016
script_path_command='realpath -m "$0"'
sbatch_block=""

# Slurm options
set +u # allow unset
if $sbatch; then
  script_path_command="scontrol show job \"\$SLURM_JOB_ID\" | awk -F= '/Command=/{print \$2}'"

  if [[ -z "$slurm_job_name" ]]; then
    if $non_interactive; then
      err "Missing --slurm-job-name in --non-interactive --sbatch mode."
      exit 1
    fi
    while [[ -z "$slurm_job_name" ]]; do
      read -r -p "$(bd "Job name") [REQUIRED]: " slurm_job_name
    done
  fi
  sbatch_block="#
`              `#SBATCH -J $slurm_job_name"

  if [[ -z "$output_file_format" ]] && ! $non_interactive; then
    read -r -p "$(bd "Output file format") (use %A_%a in the filename for job arrays, %j otherwise): " output_file_format
  fi
  if [[ -z "$output_file_format" ]]; then
    warn "Not setting output file format."
  else
    sbatch_block="$sbatch_block
`                `#SBATCH --output=$output_file_format"
  fi
fi

# Compute the relative path to the project base
# (defined as the folder containing this file.)
# https://superuser.com/questions/140590/how-to-calculate-a-relative-path-from-two-absolute-paths-in-linux-shell
base_rel_path="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2]) or "."))' "$base" "$new_file")"

touch "$new_file"
set +u
cat > "$new_file" <<-EOT
#!/bin/bash
$(comment "$description")
# 
$(comment "$explanations")
$(comment "$exit_codes")
$sbatch_block

# Get the source base folder
SCRIPT_PATH=\$($script_path_command)

base=\$(dirname "\$SCRIPT_PATH")/$base_rel_path # Project base
source "\$base"/config/utils.sh
source "\$base"/config/config.sh
set -euo pipefail
$( if $sbatch; then echo "IS_SBATCH_SCRIPT=true"; fi)

$arg_parsing_block
# ====
# MAIN
# ====
EOT

chmod +x "$new_file"
