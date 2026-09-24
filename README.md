# Ur.Terminal

Free, open source SSH client for macOS, built with Flutter. Hosts, keychain,
port forwarding, snippets and an end-to-end encrypted vault that syncs through
your own iCloud Drive, Google Drive or a private GitHub repo. No server, no
account, no subscription. iOS companion app planned.

## Features (v0.1)

- **Sync** without a server: iCloud Drive / Google Drive / Dropbox folder, or a
  private GitHub repo (`<you>/ur-terminal-vault`, one commit per sync). Records
  merge per item, so edits on two Macs do not overwrite each other
- **Import from Termius** (hosts, ports, users, passwords, keys, groups, tags,
  snippets, tunnels, known hosts) via
  [termius-local-export](https://github.com/ZeroP27/termius-local-export)
- **Myanmar and other complex scripts**: input methods (ZawCode, Pyidaungsu,
  CJK IMEs) and cross-cell shaping, so Burmese renders correctly in the shell
- **Glass UI**: native macOS blur, Termius-style tabs in the title bar,
  JetBrains Mono, adjustable transparency

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

## GitHub sync setup (once per fork)

Create an OAuth App at https://github.com/settings/applications/new, tick
**Enable Device Flow**, and put its Client ID in
`lib/sync/github_provider.dart` (`kGitHubClientId`). Client IDs are public; no
client secret is used.

## Third-party code

- `packages/xterm2`: vendored [xterm2](https://github.com/SoFluffyOS/xterm2)
  (MIT) with patches for Myanmar shaping and input-method echo
- `assets/fonts`: [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono)
  (SIL OFL 1.1)

## Roadmap

- Phase 2: Google Sign-In (Drive appData) and Sign in with Apple (CloudKit)
  sync, SFTP browser, Touch ID unlock, menu bar tunnels, split panes
- Phase 3: iOS app
- Release: Developer ID signing + notarization, Sparkle auto-update, Homebrew cask

## License

MIT
