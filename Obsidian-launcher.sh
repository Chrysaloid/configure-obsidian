#!/bin/bash

# This script is placed in ".shortcuts/tasks/Obsidian launcher" by configure-obsidian.sh
# Termux:Widget runs it in background (task) mode - no terminal, no stdin
# It self-updates via GitHub, then syncs the Obsidian vault and launches Obsidian
# On any failure it shows a dialog offering to open Obsidian anyway

set -eEu -o pipefail
# -e: exit immediately when a command fails
# -u: treat unset variables as errors
# -o pipefail: a pipeline fails if any command in it fails, not just the last one
# -E: ERR trap is inherited by functions, so _error_line is updated even if the failing command is inside a function rather than at the top level

AFTER_UPDATE="${1:-false}"

FINAL_FILE=~/".shortcuts/tasks/Obsidian launcher"

# create hidden folder for caching files and go into it
cd ~/
mkdir -p .tmp_curl_files
cd .tmp_curl_files

# these files will be created in that hidden folder
SCRIPT_FILE="Obsidian-launcher.sh"
ETAG_FILE="$SCRIPT_FILE.etag"
TMP_FILE="$SCRIPT_FILE.tmp"
LOG_FILE="LOG_FILE"

# redirect all subsequent stdout and stderr to $LOG_FILE while still printing to the terminal
# must come before the trap so error messages are captured in the log too
# also merge stderr and stdout
exec > >(tee "$LOG_FILE") 2>&1

_error_line=0
handle_errors() {
	local exit_code=$?
	if [[ $exit_code != 0 ]]; then
		local failReason
		exec 1>&- 2>&- # close stdout and stderr, signaling EOF to tee
		wait           # now tee sees EOF, flushes, and exits
		failReason="Line $_error_line produced error. Whole script's output:"$'\n'"$(cat "$LOG_FILE")"
		termux-clipboard-set "$failReason"
		if [[ "$(termux-dialog confirm \
				-t "❌ Launch failed. Report this to Chrysaloid. Do you still want to open Obsidian?" \
				-i "Fail reason (it was copied to clipboard):"$'\n'"$failReason" \
				| jq -r .text)" == "yes" ]]; then
			am start -n md.obsidian/md.obsidian.MainActivity
		fi
	fi
}

trap '_error_line=$LINENO' ERR
trap 'handle_errors' EXIT

if [[ $AFTER_UPDATE == "false" ]]; then
	echo "Attempting to update $SCRIPT_FILE"

	# Run curl to fetch the launcher script from GitHub with smart caching and robust error handling:
	# --silent: suppresses progress output for clean script execution
	# --fail: fail with error code 22 and with no response body for HTTP response codes at 400 or greater (prevents overwriting the existing script with error response)
	# --show-error: still display errors on stderr if the request fails
	# --location: follow redirects (required for GitHub/CDN routing)
	# --compressed: accept and automatically decompress encoded responses
	# --connect-timeout: maximum time in seconds that you allow curl's connection to take
	# --etag-save "$ETAG_FILE": store server ETag for future cache validation
	# --etag-compare "$ETAG_FILE": send previous ETag to enable 304 Not Modified responses
	# --output "$TMP_FILE": save downloaded content to temp file (not touched at all on 304)
	# --write-out "%{http_code}": output HTTP status code (e.g. 200, 304, 404) after request to stdout
	#
	# The command substitution captures ONLY the HTTP status code into http_code.
	# curl_exit captures curl's process exit status:
	#   0  = success (including 304 Not Modified)
	#   non-zero = network or HTTP-level failure (e.g. DNS error, timeout, 404 with --fail)
	#
	# || true would mask curl_exit so we temporarily disable set -e for this one command
	set +e
	http_code="$(
		curl \
			--silent \
			--fail \
			--show-error \
			--location \
			--compressed \
			--connect-timeout 5 \
			--etag-save "$ETAG_FILE" \
			--etag-compare "$ETAG_FILE" \
			--output "$TMP_FILE" \
			--write-out "%{http_code}" \
			"https://raw.githubusercontent.com/Chrysaloid/configure-obsidian/main/$SCRIPT_FILE"
	)"
	curl_exit=$?
	set -e

	if [[ $curl_exit != 0 ]]; then
		case $curl_exit in
			# no internet: DNS failure (Could not resolve host) | failed to connect to host | timeout
			6|7|28)
				if [[ "$(termux-dialog confirm \
						-t "❌ There is no Internet connection. Do you still want to open Obsidian?" \
						-i "If no then enable Internet yourself and try again" \
						| jq -r .text)" == "yes" ]]; then
					am start -n md.obsidian/md.obsidian.MainActivity
				fi
				exit 0
				;;
			*)
				_error_line=$LINENO # ERR won't fire on explicit exit, so set it manually
				exit $curl_exit
				;;
		esac
	fi

	if [[ $http_code == "200" ]]; then
		if [[ ! -s "$TMP_FILE" ]]; then
			# GitHub returned 200 but the response body was empty - this should never happen
			# and likely indicates a bug in curl or a GitHub-side issue; treat it as an error
			echo "curl: Downloaded file is empty" && false
		fi
		echo "$SCRIPT_FILE was updated"

		# New version downloaded successfully - atomically replace the running script and re-exec it
		# mv on the same filesystem is a single rename() syscall, so $FINAL_FILE is never missing or partial
		mv "$TMP_FILE" "$FINAL_FILE"
		chmod +x "$FINAL_FILE"
		# exec replaces the current process entirely so nothing below this block runs
		exec bash "$FINAL_FILE" true
	fi

	echo "$SCRIPT_FILE was already up to date"
fi

# 304 Not Modified (or re-exec after update) - script is current, proceed with launch

echo "Starting Obsidian launcher"

cd /storage/emulated/0/Documents/Worldbuilding

# discard local changes, get the new changes and start Obsidian if everything went OK
rm -rf .trash
git reset --hard HEAD
git pull
am start -n md.obsidian/md.obsidian.MainActivity

termux-toast -s "Happy reading! 😄"
