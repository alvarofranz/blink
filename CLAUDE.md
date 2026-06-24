# blunk

Personal fork of [Blink Shell](https://github.com/blinksh/blink) (an open-source iOS
terminal), focused on **agentic coding from the iPhone**. The on-device app is still
named "Blink"; only the GitHub repo (`blunk`) and this project's direction are customized.

- Origin: `alvarofranz/blunk`  ·  Upstream: `blinksh/blink`
- Working branch: `raw`  ·  Bundle id: `com.alvarofranz.blink`

## Build & run on a device

Prereqs: the full **Xcode.app** (not just Command Line Tools), an Apple signing team,
and an iPhone with Developer Mode enabled.

One-time, after a fresh clone:

```bash
git submodule update --init                          # MBProgressHUD is built from source
./get_frameworks.sh                                  # prebuilt xcframeworks -> xcfs/.build (NEEDS full Xcode)
./get_resources.sh                                   # vim runtime
cp template_setup.xcconfig developer_setup.xcconfig  # then edit: set TEAM_ID + bundle/group/cloud ids
```

Iterate (build + install + launch on the connected iPhone, no Xcode UI needed):

```bash
./deploy.sh                                          # incremental; auto-detects the device, or set BLINK_DEVICE_ID
```

### Signing config

`developer_setup.xcconfig` is **gitignored** and required. It holds the personal
`TEAM_ID`, the bundle/group/cloud/keychain ids, and a copy of the build-compat flags
below. The non-personal flags also live in the tracked `template_setup.xcconfig`, so a
fresh clone keeps building after the copy step.

### Why the build-compat flags exist (Xcode 16+/26)

Blink dispatches its built-in commands (`config`, `ssh`, `mosh`, ...) via
`dlsym(RTLD_MAIN_ONLY, <cmd>_main)` against the **main executable**. Modern Xcode breaks
that, so this fork sets (in `template_setup.xcconfig`):

- `ENABLE_DEBUG_DYLIB = NO` — Xcode 16+ otherwise moves the app code into
  `Blink.debug.dylib` and leaves a thin launcher as the main executable, so
  `dlsym(RTLD_MAIN_ONLY)` finds none of the command symbols.
- `BLINK_OTHER_LDFLAGS = -Xlinker -export_dynamic` — exports the executable's global
  symbols so `dlsym` can resolve them.

Also: every target uses `DEVELOPMENT_TEAM = $(TEAM_ID)` (instead of a hardcoded team),
and the `com.apple.developer.web-browser` entitlement is removed (it needs Apple approval
and blocks signing on a standard account).

## Staying in sync with upstream

```bash
git fetch upstream
git merge upstream/raw      # merge model: simple, no history rewrite, no force-push
```

We use **merge** (not rebase) so the already-pushed `raw` never needs a force-push. When a
change is generic and non-personal (e.g. the build-compat flags above), prefer sending it
**upstream as a PR** to shrink this fork's permanent delta.

## Modularity rules (keep merges painless)

Breaking Blink's behavior is fine; what must stay small is the **diff footprint in
upstream files**. Merge pain is proportional to how much shared code you edit.

- **Add, don't modify.** Put new behavior in **new files/modules**. New files never cause
  merge conflicts.
- **One-line seams.** Where hooking into upstream code is unavoidable, make it a single
  line that delegates to a fork module — not a large inline edit (see the Blunk seams
  table below for real examples).
- Categorize every change: **(a)** generic build/compat fixes → upstream PRs;
  **(b)** personal config → gitignored; **(c)** fork features → new modules behind seams.

## Blunk: the input model

Blunk turns the terminal into a **compose-first** agent client. The terminal is a
read-only transcript; all input goes through Blunk's own UI. All behaviour lives in two
new, self-contained files plus a handful of tiny seams.

**New files (this is where the features live):**

- `Blink/Blunky.swift` — the `Blunk` feature flag, **Blunkitor** (the full-screen prose
  composer: system keyboard + dictation, a command-completion suggestions strip, the Snips
  gallery, paste), and `BlunkySnipsPicker` (reads/writes `.blink/snippets/<folder>/*.sh`).
- `Blink/Blunkeys.swift` — **Blunkeys**, the floating round quick-key buttons on the main
  view that send keys live to the agent/TUI: `⌃` (special), `123`, `abc`, `↕` (arrows),
  and a standalone `⏎`.

**The seams into upstream (keep these minimal):**

| File | Seam |
|------|------|
| `Blink/SmarterKeys/SmarterTermInput.swift` | `becomeFirstResponder()` returns `false` under `Blunk.scratchOnly` → the terminal never shows a keyboard. |
| `Blink/WebKit/WKWebView.swift` | `_on1fTap` routes a terminal tap to `openBlunkitor` instead of focusing the terminal. |
| `Blink/SpaceController.swift` | one line `Blunkeys.install(in:)`; plus `canBecomeFirstResponder` + `viewDidAppear` becoming first responder, so chain-dispatched commands (`config`, …) still reach SpaceController while the terminal is keyboard-less. |

Everything is gated by `Blunk.scratchOnly` (in `Blunky.swift`). Set it to `false` to fall
back to stock Blink input (on-terminal keyboard + SmartKeys bar).

## Ideas / not done yet

- Richer Blunkitor completions (paths/hosts via `Complete._for`, debounced on a background
  queue). Today it completes Blink **command names** only, and only in command position —
  and it is local-shell-aware, not remote-agent-aware.
- Image attach for remote agents: upload the photo over sftp/scp and inject its remote
  path into the prompt — not clipboard simulation, because the agent runs on the remote
  host and `Ctrl+V` would read the wrong machine's clipboard.
