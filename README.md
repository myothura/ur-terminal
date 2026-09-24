# Ur.Terminal

Free, open source SSH client for macOS, built with Flutter. Hosts, keychain,
port forwarding, snippets and an end-to-end encrypted vault that syncs through
your own Google Drive, GitHub or iCloud. iOS companion app planned.

## Features (v0.1)

- **Hosts** with groups, tags, search, identities and ProxyJump chains
- **Terminal** tabs (SSH and local shell), xterm-256color, auto-reconnect on Enter
- **Port forwarding**: Local `-L`, Remote `-R`, Dynamic SOCKS5 `-D`, auto-start,
  automatic reconnect with backoff, live traffic counters
- **Keychain**: generate Ed25519, import from `~/.ssh`, one-click install of a
  public key on a server
- **Snippets** with `{{placeholders}}`, run in a tab or on many hosts in parallel
- **2FA**: stores a TOTP secret per host and auto-answers
  `Verification code:` prompts (libpam-google-authenticator)
- **Known hosts** (TOFU) with loud warning on changed keys
- Import `~/.ssh/config`
- Command palette (`Cmd+K`)

## Security model

```
master password --Argon2id--> KEK --wraps--> random 256-bit data key
data key --XChaCha20-Poly1305--> each record (id + type bound as AAD)
```

Nothing leaves the Mac unencrypted. Sync backends only store the sealed vault.
The master password cannot be recovered.

## Keyboard

| Keys | Action |
|---|---|
| Cmd+K | Command palette |
| Cmd+T | New local terminal |
| Cmd+W | Close tab |
| Cmd+1..9 / Cmd+0 | Switch tab / vault |
| Ctrl+Tab | Next tab |
| Cmd+N | New host |
| Cmd+L | Lock |

## Build

Requires Flutter 3.35+ and Xcode.

```bash
./tool/setup.command   # creates platform folders, pub get, analyze, test
./tool/run.command     # flutter run -d macos
```

## Roadmap

- Phase 2: Google Drive / GitHub / iCloud sync, SFTP browser, Touch ID unlock,
  menu bar tunnels, split panes
- Phase 3: iOS app
- Release: Developer ID signing + notarization, Sparkle auto-update, Homebrew cask

## License

MIT
