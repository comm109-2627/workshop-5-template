#!/usr/bin/env bash

# Automatically detect the workspace root
WORKSPACE_DIR=$(pwd)
echo "RUNNING SETUP SCRIPT FOR $WORKSPACE_DIR"

# 1. Install Python requirements cleanly
if [ -f "$WORKSPACE_DIR/.profile/requirements.txt" ]; then
    python -m pip install --no-cache-dir -r "$WORKSPACE_DIR/.profile/requirements.txt"
fi

# 2. Safely swap .bashrc
if [ ! -L ~/.bashrc ]; then
    mv ~/.bashrc ~/.bashrc.backup 2>/dev/null || true
fi
if [ -f "$WORKSPACE_DIR/.profile/bashrc" ]; then
    ln -sf "$WORKSPACE_DIR/.profile/bashrc" ~/.bashrc
fi

# 3. Persist bash history (Ensure .profile/bash_history is in .gitignore!)
if [ "$SYNC_BASH_HISTORY" = "true" ]; then
    touch "$WORKSPACE_DIR/.profile/bash_history"
    ln -sf "$WORKSPACE_DIR/.profile/bash_history" ~/.bash_history
    echo "Bash history syncing ENABLED."
else
    # Clean up symlink if history syncing is turned off later
    if [ -L ~/.bash_history ]; then
        rm ~/.bash_history
        touch ~/.bash_history
    fi
fi

# 4. Setup git helper executable
mkdir -p ~/.local/bin
if [ -f "$WORKSPACE_DIR/.profile/git_helper.sh" ]; then
    chmod u+x "$WORKSPACE_DIR/.profile/git_helper.sh"
    ln -sf "$WORKSPACE_DIR/.profile/git_helper.sh" ~/.local/bin/git_helper
fi

# Silently disable Copilot CLI auto-updates if the directory exists
sudo rm -rf /etc/devcontainer-copilot-cli 2>/dev/null || true

echo "ENDED SETUP SCRIPT"
