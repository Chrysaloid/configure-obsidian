#!/bin/bash

# this script will be downloaded once and put in ".shortcuts/tasks/Obsidian launcher"

configRun="${1:-false}"

# create hidden folder for caching files and go into it
cd ~/
mkdir -p .tmp_curl_files
cd .tmp_curl_files

# these files will be created in that hidden folder
ETAG_FILE="Obsidian-launcher.etag"
SCRIPT_FILE="Obsidian-launcher.sh"
LOG_FILE="LOG_FILE"
EXIT_FILE="EXIT_FILE"

# Run curl to fetch the launcher script from GitHub with smart caching and robust error handling:
# --silent: suppresses progress output for clean script execution
# --fail: fail with error code 22 and with no response body for HTTP response codes at 400 or greater (prevents overwriting the existing script with error response)
# --show-error: still display errors on stderr if the request fails
# --location: follow redirects (required for GitHub/CDN routing)
# --compressed: accept and automatically decompress encoded responses
# --etag-save "$ETAG_FILE": store server ETag for future cache validation
# --etag-compare "$ETAG_FILE": send previous ETag to enable 304 Not Modified responses
# --output "$SCRIPT_FILE": save downloaded script to local file
# --write-out "%{http_code}": output HTTP status code (e.g. 200, 304, 404) after request to stdout
#
# The command substitution captures ONLY the HTTP status code into http_code.
# lastExitCode ($?) captures curl's process exit status:
#   0  = success (including 304 Not Modified)
#   non-zero = network or HTTP-level failure (e.g. DNS error, timeout, 404 with --fail)
http_code="$(
	curl \
		--silent \
		--fail \
		--show-error \
		--location \
		--compressed \
		--etag-save "$ETAG_FILE" \
		--etag-compare "$ETAG_FILE" \
		--output "$SCRIPT_FILE" \
		--write-out "%{http_code}" \
		"https://raw.githubusercontent.com/Chrysaloid/configure-obsidian/main/$SCRIPT_FILE"
)"
lastExitCode=$?

failReason=""
if [[ $lastExitCode != 0 ]]; then # when curl returned error exit code
	case $lastExitCode in
		6) failReason="Could not resolve host" ;;
		7) failReason="Could not connect to server" ;;
		22) failReason="HTTP error $http_code" ;;
		28) failReason="Connection timed out" ;;
		*) failReason="Download failed (curl exit code $lastExitCode)" ;;
	esac
else
	echo "Starting Obsidian launcher"
	# run script and pass all arguments of this script to it also stream to current console and save to file
	{
		bash -e "$SCRIPT_FILE" -- "$@"
		# -e: exit immediately on error
		# -u: Treat unset variables and parameters as an error when performing parameter expansion
		echo $? > "$EXIT_FILE" # exit code is preserved separately (critical because pipes hide $?)
	} 2>&1 | tee "$LOG_FILE"
	lastExitCode="$(cat "$EXIT_FILE")"
fi

if [[ $lastExitCode != 0 && "$configRun" == "false" ]]; then # when curl or bash returned error exit code and we are not during config
	if [[ -z "$failReason" ]]; then # check for empty string, will be empty when bash returned error exit code
		failReason="$(cat "$LOG_FILE")"
	fi
	termux-clipboard-set "$failReason"
	if [[ "$(termux-dialog confirm -t "❌ Launch failed. Report this to Chrysaloid. Do you still want to open Obsidian?" -i "Fail reason (it was copied to clipboard):"$'\n'"$failReason" | jq -r .text)" = "yes" ]]; then
		am start -n md.obsidian/md.obsidian.MainActivity
	fi
fi
