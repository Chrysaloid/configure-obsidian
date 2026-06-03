#!/bin/bash

echo "Starting Obsidian launcher"

set -u # is a Bash option that makes your script fail fast on undefined variables

VERBOSE="${1:-false}"

run_step() {
	local name="$1"
	shift
	local cmd=("$@")

	local output
	local exitCode

	output="$("${cmd[@]}" 2>&1)"
	exitCode=$?

	if [ "$VERBOSE" = "true" ]; then
		echo "$output"
	fi

	if [ $exitCode -ne 0 ]; then
		failOutput="Command: $name"$'\n'"Exit code: $exitCode"$'\n'"$output"
		termux-clipboard-set "$failOutput"

		if [[ "$(termux-dialog confirm -t "❌ Launch failed. Do you still want to open Obsidian?" -i "Fail output (it was copied to clipboard): $failOutput" | jq -r .text)" == "yes" ]]; then
			am start -n md.obsidian/md.obsidian.MainActivity
		fi

		return $exitCode
	fi

	return 0
}

cd /storage/emulated/0/Documents/Worldbuilding

# discards local changes, get the new changes and start obsidian if everything went OK
run_step "rm trash" rm -rf .trash || exit $?
run_step "git reset" git reset --hard HEAD || exit $?
run_step "git pull" git pull || exit $?
run_step "open obsidian" am start -n md.obsidian/md.obsidian.MainActivity || exit $?

termux-toast -s "Happy reading! 😄"
