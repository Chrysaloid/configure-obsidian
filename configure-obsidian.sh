#!/bin/bash

# This script configures git and Obsidian on a phone with Termux. Do not run it on an arbitrary Linux as it will eventually fail

# Before running this script make sure that these apps are installed:
# https://f-droid.org/en/packages/com.termux/ (obviously)
# https://f-droid.org/en/packages/com.termux.api/ (for displaying toast messages)
# https://f-droid.org/en/packages/com.termux.widget/ (for adding script shortcuts)
# Then open Termux:API app and grant it "Disable android battery optimisation" and "Display over other apps" perrmisions (there will be buttons to do this, just click them)

# Use this command to run this script in its most updated version:
# curl -fsSL --compressed "https://raw.githubusercontent.com/Chrysaloid/configure-obsidian/main/configure-obsidian.sh" | bash
# Explanation:
# This command downloads the script from GitHub and runs it using bash
# curl -f option means "fail on HTTP errors" (don't pipe ex. a 404 page into bash)
# curl -s option means "Silent mode" so curl won't print anything on it's own, only bash will then print various outpus while running this script
# curl -S option means "still show errors when -s is used" (they will be printed on stderr so they will NOT be piped do bash)
# curl -L option means "Follow redirects", necessary as GitHub uses them sometimes
# curl --compressed option causes curl to send "Accept-Encoding: deflate, gzip, br, zstd"

# After running this script:
# - go to home screen
# - hold down until customisation mode shows up
# - go to widgets and search for "Termux:Widget"
# - add "Termux shortcut"
# - in the menu that appears pick "tasks/" folder
# - pick "Obsidian launcher"
# - click "Add" (lub "Dodaj" po Polsku)
# - click the newly added shortcut to test it
# - optionally remove main Obsidian app icon from home screen to avoid confusion in the future

# To clarify: the toast that is shown after starting the shortcut does not slow down the Obsidian start up - they are independent

cd ~/ # make sure we are in the home folder

set -e # Exit immediately on error

echo -e "----------------- START -----------------\n"

# upgrade and install packages non-interactively
pkg upgrade -y -o Dpkg::Options::="--force-confold"
pkg install -y git gh termux-api jq
echo ""

# login only when not logged in
gh auth status || gh auth login --hostname github.com --git-protocol https --web

# skip prompt if already set up
yes | termux-setup-storage

# prepare folders
mkdir     -p                  .shortcuts
chmod 700 -R                  .shortcuts
mkdir     -p                  .shortcuts/tasks
chmod 700 -R                  .shortcuts/tasks
mkdir     -p                  .shortcuts/icons
chmod     -R a-x,u=rwX,go-rwx .shortcuts/icons

# only when file does not exist
if [[ ! -f ".shortcuts/icons/Obsidian launcher.png" ]]; then
	curl --output ".shortcuts/icons/Obsidian launcher.png" https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/2023_Obsidian_logo.svg/500px-2023_Obsidian_logo.svg.png
	echo ""
fi

# the shortcut we create will first download it's newest version then run it. We pass all arguments to it
curl -fsSL --compressed -o ".shortcuts/tasks/Obsidian launcher" "https://raw.githubusercontent.com/Chrysaloid/configure-obsidian/main/real-Obsidian-launcher.sh"
# -f -> Fail fast with no output on HTTP errors
# -o -> Write to file instead of stdout
# -s -> Silent mode
# -S -> Show error even when -s is used
# -L -> Follow redirects
# --compressed -> Request compressed response

# make scripts executable
chmod +x ~/.shortcuts/*
chmod +x ~/.shortcuts/tasks/*

# remove old cached scripts just in case
rm -rf .tmp_curl_files

# only when dir does not exist
if [[ ! -d /storage/emulated/0/Documents/Worldbuilding ]]; then
	cd /storage/emulated/0/Documents/

	# core.quotepath true will quote "unusual" characters in the pathname by enclosing the pathname
	# in double-quotes and escaping those characters with backslashes in the same way C escapes
	# control characters (e.g. \t for TAB, \n for LF, \\ for backslash) or bytes with values larger
	# than 0x80 (e.g. octal \302\265 for "micro" in UTF-8). core.quotepath false will not do that
	git config --global core.quotepath false

	# set correct git user using gh api
	git config --global user.name "$(gh api user --jq .login)"
	git config --global user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"

	gh repo clone Michal-Roman0/Worldbuilding
	cd Worldbuilding

	# skip checking for changes and updating files that are frequently changed by Obsidian
	git update-index --skip-worktree .obsidian/plugins/recent-files-obsidian/data.json
	git update-index --skip-worktree .obsidian/workspace.json
	# also skip this file if you want to ex. edit font or other UI styles
	# git update-index --skip-worktree ".obsidian/themes/ITS Theme/theme.css"

	# to undo above commands use the following commands
	# git update-index --no-skip-worktree .obsidian/plugins/recent-files-obsidian/data.json
	# git update-index --no-skip-worktree .obsidian/workspace.json
	# git update-index --no-skip-worktree ".obsidian/themes/ITS Theme/theme.css"

	echo ""
fi

# run launcher script
~/".shortcuts/tasks/Obsidian launcher" true

echo -e "\n----------------- DONE -----------------"
