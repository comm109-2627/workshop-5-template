#!/usr/bin/env bash

# --- Configuration ---
SLEEP_INTERVAL=10
SHADOW_BASE_DIR="/tmp/autosave-shadows"
MAIN_BRANCH_NAME="main"
AUTOSAVE_BRANCH_NAME="autosave"
# ---------------------

# --- Halt Flag Check ---
if [ "${1:-}" == "-h" ]; then
    echo "Stopping all watcher processes..."
    pgrep -f "$0" | grep -v $$ | xargs -r kill
    exit 0
fi

if [ $# -eq 0 ]; then
    ### LAUNCHER MODE ###
    TARGET_DIR=$(pwd)
    
    echo "Stopping old watcher processes..."
    pgrep -f "$0" | grep -v $$ | xargs -r kill
    
    LOG_FILE="/tmp/auto-commit.log"
    echo "Starting watcher for $TARGET_DIR..."
    
    nohup bash "$0" "$TARGET_DIR" > "$LOG_FILE" 2>&1 &
    exit 0
    
else
    ### WATCHER MODE ###
    TARGET_DIR="$1"
    LOCK_NAME=$(echo "$TARGET_DIR" | tr -c 'a-zA-Z0-9' '_')
    LOCKFILE="/tmp/auto-commit-lock-$LOCK_NAME.lock"

    exec 200>"$LOCKFILE"
    flock -n 200 || exit 1
    
    trap 'exec 200>&-; exit 0' SIGINT SIGTERM
    
    # Check if on Main Branch
    CURRENT_BRANCH=$(git -C "$TARGET_DIR" rev-parse --abbrev-ref HEAD)
    if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH_NAME" ]; then
        echo "Not on $MAIN_BRANCH_NAME. Exiting."
        exit 1
    fi

    # Set up Shadow Repo
    SHADOW_DIR="$SHADOW_BASE_DIR/$LOCK_NAME"
    mkdir -p "$SHADOW_BASE_DIR"
    rm -rf "$SHADOW_DIR"
    
    git clone "$TARGET_DIR" "$SHADOW_DIR" || exit 1
    cd "$SHADOW_DIR" || exit 1
    
    git config user.email "autosave@codespaces.local"
    git config user.name "Autosave Bot"
    git config push.autoSetupRemote true

    # Configure Remote Auth & Push Access
    REAL_ORIGIN_URL=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null)
    CAN_PUSH=true
    
    if [ -z "$REAL_ORIGIN_URL" ]; then
        CAN_PUSH=false
    elif [ -n "$GITHUB_TOKEN" ]; then
        TOKENIZED_URL=$(echo "$REAL_ORIGIN_URL" | sed "s|https://|https://$GITHUB_TOKEN@|")
        git remote set-url origin "$TOKENIZED_URL"
    fi
    
    # Branch Setup
    if git fetch origin 2>/dev/null; then
        if git show-ref --verify --quiet "refs/remotes/origin/$AUTOSAVE_BRANCH_NAME"; then
            git checkout "$AUTOSAVE_BRANCH_NAME"
        else
            git checkout -b "$AUTOSAVE_BRANCH_NAME"
            echo "WARNING: Automated branch." > WARNING.txt
            git add WARNING.txt
            git commit -m "Init autosave"
            git push origin "$AUTOSAVE_BRANCH_NAME" || CAN_PUSH=false
        fi
    else
        git checkout -b "$AUTOSAVE_BRANCH_NAME" 2>/dev/null || git checkout "$AUTOSAVE_BRANCH_NAME"
        CAN_PUSH=false
    fi
    
    # Main Watcher Loop
    while true
    do
        if [ "$CAN_PUSH" = true ]; then
            git fetch origin 2>/dev/null
            git reset --hard "origin/$AUTOSAVE_BRANCH_NAME" 2>/dev/null || true
        fi
        
        rsync -a --delete --exclude=".git" "$TARGET_DIR/" "$SHADOW_DIR/"
        
        echo "WARNING: This is an automated branch. Do not work here." > WARNING.txt
        git add .
        
        if [ -n "$(git status --porcelain)" ]; then
            git commit -m "auto-commit: $(date +'%Ym%d-%H%M%S')"
            
            if [ "$CAN_PUSH" = true ]; then
                git push origin "$AUTOSAVE_BRANCH_NAME" 2>/dev/null || true
            fi
        fi
        
        sleep "$SLEEP_INTERVAL"
    done
fi