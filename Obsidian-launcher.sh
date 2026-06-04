#!/bin/bash

cd /storage/emulated/0/Documents/Worldbuilding

# discards local changes, get the new changes and start obsidian if everything went OK
rm -rf .trash
git reset --hard HEAD
git pull
am start -n md.obsidian/md.obsidian.MainActivity

termux-toast -s "Happy reading! 😄"
