#!/usr/bin/env bash
#
checkbrew() {

    if hash brew 2>/dev/null; then
        #brew update
        #brew upgrade
        #if !hash munki 2>/dev/null; then
            brew cask install munki
        #fi
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        checkbrew
    fi
}
if [[ "$OSTYPE" == "darwin"* ]]; then
    checkbrew
    python ./fetch-macOS.py
else
    echo This is a macOS specific application - No support for $OSTYPE planned
fi

