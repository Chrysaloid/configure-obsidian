#!/bin/bash

# this script will be downloaded once and put in ".shortcuts/tasks/Obsidian launcher"

etagFile="Obsidian-launcher.etag"
scriptFile="Obsidian-launcher.sh"

cd ~/
mkdir -p .tmp_curl_files
cd .tmp_curl_files

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

if [[ $curlExitCode -ne 0 ]]; then
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

bash "$scriptFile" -- "$@"
