#!/bin/bash

# this script will be downloaded once and put in ".shortcuts/tasks/Obsidian launcher"

etagFile="Obsidian-launcher.etag"
scriptFile="Obsidian-launcher.sh"

# create hidden folder for caching files and go into it
cd ~/
mkdir -p .tmp_curl_files
cd .tmp_curl_files

# Run curl to fetch the launcher script from GitHub with smart caching and robust error handling:
# --silent: suppresses progress output for clean script execution
# --show-error: still display errors on stderr if the request fails
# --location: follow redirects (required for GitHub/CDN routing)
# --compressed: accept and automatically decompress encoded responses
# --etag-save "$etagFile": store server ETag for future cache validation
# --etag-compare "$etagFile": send previous ETag to enable 304 Not Modified responses
# --output "$scriptFile": save downloaded script to local file
# --write-out "%{http_code}": output HTTP status code (e.g. 200, 304, 404) after request to stdout
#
# The command substitution captures ONLY the HTTP status code into http_code.
# curlExitCode ($?) captures curl's process exit status:
#   0  = success (including 304 Not Modified)
#   non-zero = network or HTTP-level failure (e.g. DNS error, timeout, 404 with --fail)
http_code="$(
	curl \
		--silent \
		--show-error \
		--location \
		--compressed \
		--etag-save "$etagFile" \
		--etag-compare "$etagFile" \
		--output "$scriptFile" \
		--write-out "%{http_code}" \
		"https://raw.githubusercontent.com/Chrysaloid/configure-obsidian/main/$scriptFile"
)"
curlExitCode=$?

if [[ $curlExitCode -ne 0 ]]; then # when curl returned error exit code
	case $curlExitCode in
		6) errorReason="Could not resolve host" ;;
		7) errorReason="Could not connect to server" ;;
		22) errorReason="HTTP error $http_code" ;;
		28) errorReason="Connection timed out" ;;
		*) errorReason="Download failed (curl exit code $curlExitCode)" ;;
	esac
	termux-clipboard-set "$errorReason"
	if [[ "$(termux-dialog confirm -t "❌ Launch failed. Do you still want to open Obsidian?" -i "Fail reason (it was copied to clipboard):"$'\n'"$errorReason" | jq -r .text)" = "yes" ]]; then
		am start -n md.obsidian/md.obsidian.MainActivity
	fi
	exit $curlExitCode
fi

# run script and pass all arguments of this script to it
bash "$scriptFile" -- "$@"
