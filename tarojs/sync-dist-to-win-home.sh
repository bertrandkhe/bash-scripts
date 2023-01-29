#!/bin/bash

# Skip if not WSL
if [ -z "$(uname -a) | grep WSL" ]; then
  echo "This script is made for WSL2. Does not work on other OSes. Exit."
  exit 0
fi

if [ -z "$(which inotifywait)" ]; then
  echo "Command 'inotifywait' is missing. You can install it by running:"
  echo "sudo apt-get install inotify-tools"
  exit 1
fi

# Sync project dist folder to $DST/dist or $WIN_HOME/WechatProjects/$PROJECT/dist
DST=$1
PROJECT="$(basename $(pwd))"

if [ -z "$DST" ]; then
  # Try to find out user's home on Windows. 
  # It should be located at /mnt/c/users/$USERNAME
  if [ -z "$WIN_HOME" ]; then
    # whoami.exe return the user FQN, we only care about the username
    USERNAME="$(echo "$(whoami.exe)" | awk -F'\\\' '{ print $NF }')"
    # Windows does not care about case
    WIN_HOME="/mnt/c/users/$USERNAME"
    if [ ! -d "$WIN_HOME" ]; then 
      echo "Unable to find out user's home directory." 
      echo "Expect user's home directory to be at $WIN_HOME but nothing found at this location."
      exit 1
    fi
  fi 
  # Create project dir in $WIN_HOME if it does not exist
  DST="$WIN_HOME/WechatProjects/$PROJECT"
  if [ ! -d "$DST" ]; then
    echo "[$(date --iso-8601=seconds)] CREATING folder $DST"
    mkdir -p "$DSP"
  fi
fi

if [ ! -d "$DST" ]; then
  echo "Destination direction $DST does not exist."
  exit 1
fi

# ./dist/emittedAssets.txt contains the list of files emitted by webpack.
# If this file does not exist, the project is not yet compiled.
# This file is used by rsync to transfer files to $DST.
if [ ! -f "./dist/emittedAssets.txt" ]; then
  echo "[$(date --iso-8601=seconds)] Waiting for compilation to be done."
  if [ ! -d "./dist" ]; then
    mkdir dist
  fi
  while inotifywait -qq -e create ./dist; do
    if [ -f "./dist/emittedAssets.txt" ]; then
      echo "[$(date --iso-8601=seconds)] Compilation done."
      break
    fi
  done
fi

# First pass, transfer everything.
# Do not use -v option in rsync, do no try to sync permissions from WSL to Windows, NTFS is not POSIX compliant
echo "[$(date --iso-8601=seconds)] START: Full sync to $DST"
rsync -cr --delete ./dist $DST
rsync -cr ./project.config.json $DST
echo "[$(date --iso-8601=seconds)] DONE: Full sync to $DST"

# Only transfer updated files.
while inotifywait -qq -e modify ./dist/emittedAssets.txt; do
    echo "---------------------------------------------------------"
    echo "[$(date --iso-8601=seconds)] START: Syncing files to $DST"
    while read LINE; do
      cp "./dist/$LINE" "$DST/dist/$LINE"
    done < ./dist/emittedAssets.txt
    NB_FILES=$(cat ./dist/emittedAssets.txt | nl | tail -n 1 | awk '{ print $1 }')
    echo "[$(date --iso-8601=seconds)] DONE: $NB_FILES files synced to $DST"
done
