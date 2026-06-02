#!/bin/bash

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
      termux-toast -s "❌ Error in: $name (output copied to clipboard)"

      {
         echo "Command: $name"
         echo "Exit code: $exitCode"
         echo
         echo "$output"
      } | termux-clipboard-set

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

# copy launcher script to a correct location and remove its extension
# the effect of changes will be visible on the next launch
cp -u "Obsidian launcher.sh" ~/".shortcuts/tasks/Obsidian launcher"

termux-toast -s "Happy reading! 😄"
