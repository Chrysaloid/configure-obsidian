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
		# state the failing line in the log itself, while stdout still goes through tee, so
		# that a log pasted on its own is self-diagnosing - previously this number existed
		# only in the dialog and the clipboard and got lost whenever those were not kept
		echo "Line $_error_line produced error (exit code $exit_code)"
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

	case $curl_exit in
		0) ;; # success, do nothing
		6|7|28)
			# no internet: DNS failure (Could not resolve host) | failed to connect to host | timeout
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

# Files whose LOCAL version always wins over whatever comes from the remote.
# They carry the --skip-worktree bit so git ignores the constant rewrites Obsidian
# does to them, but that bit only hides OUR edits - it does not protect against
# INCOMING ones. Verified behaviour when a commit upstream touches such a file:
#   - git reset --hard HEAD leaves the file (and the bit) completely alone
#   - git pull then aborts with "Your local changes ... would be overwritten by merge"
# which would make every launch from then on fail until someone fixed it by hand.
# So we save our copies, let the merge land normally, then put our copies back.
# Add more paths here as needed - relative to the repo root, quoted, one per line.
LOCAL_PRIORITY_FILES=(
	".obsidian/workspace.json"
	".obsidian/workspaces.json"
	".obsidian/plugins/recent-files-obsidian/data.json"
	".obsidian/plugins/obsidian-git/obsidian_askpass.sh"
	# uncomment if you want to keep ex. a locally edited font or other UI styles
	# ".obsidian/themes/ITS Theme/theme.css"
)

BACKUP_DIR=~/.tmp_curl_files/local_priority_backup

# download the new commits without touching the working tree yet, so we can look at what
# is coming before deciding whether any of the files above have to be saved at all
git fetch

# paths that the incoming commits change - empty string when we are already up to date.
# @{u} is the upstream branch (origin/main), so this lists exactly what the merge below
# will modify. -c core.quotepath=false keeps non-ASCII paths unescaped so that they can
# be compared literally against the entries of LOCAL_PRIORITY_FILES
CHANGED_FILES="$(git -c core.quotepath=false diff --name-only HEAD..@{u})"

# save only those protected files that the incoming commits really touch - which is
# almost always none of them, and then nothing is copied and no directory is created
STASHED_FILES=()
for file in "${LOCAL_PRIORITY_FILES[@]}"; do
	[[ -f $file ]] || continue                            # not present locally (ex. new entry in the list) - nothing to preserve
	grep -qxF -- "$file" <<< "$CHANGED_FILES" || continue # untouched upstream - the merge will not disturb it, leave it alone
	if (( ${#STASHED_FILES[@]} == 0 )); then
		rm -rf "$BACKUP_DIR" # first file of this run - clear anything an interrupted earlier run left behind
	fi
	mkdir --parents "$BACKUP_DIR/$(dirname "$file")"
	cp --preserve "$file" "$BACKUP_DIR/$file"
	if git ls-files --error-unmatch -- "$file" > /dev/null 2>&1; then
		# tracked: drop the bit so that reset + merge may freely overwrite it
		git update-index --no-skip-worktree -- "$file"
	else
		# untracked here but added upstream - merge refuses to clobber such a file, and
		# we already hold a copy of it, so get it out of the way
		rm -f "$file"
	fi
	STASHED_FILES+=("$file")
done

# discard local changes and apply the commits fetched above
# (git merge instead of git pull - the fetch already happened, and --no-edit stops git from
# trying to open an editor for the merge message when the vault has local commits to merge)
rm -rf .trash
git reset --hard HEAD
git merge --no-edit @{u}

# put our versions back on top of whatever arrived
if (( ${#STASHED_FILES[@]} > 0 )); then
	for file in "${STASHED_FILES[@]}"; do
		mkdir --parents "$(dirname "$file")"
		cp --preserve "$BACKUP_DIR/$file" "$file"
	done
	rm -rf "$BACKUP_DIR"
fi

# Make sure every protected file is hidden from git again. One git call, no file I/O, so it
# is cheap enough to run unconditionally - and it is what sets the bits in the first place on
# a freshly cloned vault, as well as what restores the ones dropped by the loop above.
# ls-files -v prints one "<tag> <path>" line per tracked file, where the tag is S for
# skip-worktree; paths that are not tracked simply produce no line
while IFS= read -r line; do
	if [[ ${line:0:1} != "S" ]]; then
		git update-index --skip-worktree -- "${line:2}"
	fi
done < <(git -c core.quotepath=false ls-files -v -- "${LOCAL_PRIORITY_FILES[@]}")

# start Obsidian if everything went OK
am start -n md.obsidian/md.obsidian.MainActivity

termux-toast -s "Happy reading! 😄"
