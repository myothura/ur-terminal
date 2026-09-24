#!/bin/zsh
# Build and launch Ur.Terminal on macOS. Output is also written to .cowork/run.log
cd "$(dirname "$0")/.." || exit 1
[ -x "$HOME/Development/flutter/bin/flutter" ] && export PATH="$HOME/Development/flutter/bin:$PATH"
mkdir -p .cowork
flutter run -d macos 2>&1 | tee .cowork/run.log
