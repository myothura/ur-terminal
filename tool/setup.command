#!/bin/zsh
# Ur.Terminal - one-shot project setup. Double-click in Finder or run: ./tool/setup.command
# Output is also written to .cowork/setup.log
cd "$(dirname "$0")/.." || exit 1
[ -x "$HOME/Development/flutter/bin/flutter" ] && export PATH="$HOME/Development/flutter/bin:$PATH"
mkdir -p .cowork
LOG=.cowork/setup.log

{
  echo "== Ur.Terminal setup  $(date)"
  flutter --version || { echo "flutter not found"; exit 1; }

  if [ ! -d macos ]; then
    echo "== flutter create (platform folders)"
    flutter create --org com.goodbrother --project-name ur_terminal \
      --platforms macos,ios --no-pub . || exit 1
  fi

  echo "== macOS config"
  cp tool/macos/DebugProfile.entitlements tool/macos/Release.entitlements macos/Runner/
  cp tool/macos/MainFlutterWindow.swift macos/Runner/MainFlutterWindow.swift
  sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = UrTerminal/' macos/Runner/Configs/AppInfo.xcconfig
  sed -i '' 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = com.goodbrother.urterminal/' macos/Runner/Configs/AppInfo.xcconfig
  sed -i '' 's/^PRODUCT_COPYRIGHT = .*/PRODUCT_COPYRIGHT = Copyright 2026 Sunix Technology. MIT License./' macos/Runner/Configs/AppInfo.xcconfig
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Ur.Terminal" macos/Runner/Info.plist 2>/dev/null
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Ur.Terminal" macos/Runner/Info.plist 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Ur.Terminal" macos/Runner/Info.plist
  /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.developer-tools" macos/Runner/Info.plist 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" macos/Runner/Info.plist
  sed -i '' 's/com\.goodbrother\.urTerminal/com.goodbrother.urterminal/g' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Ur.Terminal" ios/Runner/Info.plist 2>/dev/null

  echo "== flutter pub get"
  flutter pub get || exit 1

  echo "== flutter analyze"
  flutter analyze --no-fatal-infos
  echo "ANALYZE_EXIT=$?"

  echo "== flutter test"
  flutter test
  echo "TEST_EXIT=$?"

  if [ ! -d .git ]; then
    git init -q && git add -A && git commit -qm "Ur.Terminal: initial scaffold" && echo "== git initialized"
  fi
  echo "== done"
} 2>&1 | tee "$LOG"
