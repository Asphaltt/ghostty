# Experimental Floating Tabs

## Personal build

From the repository root:

```sh
make app
make open
make install
make test
```

`make`, `make build`, and `make app` build the native GhosttyKit framework with
Zig, then the macOS app using `macos/build.nu`. The bundle is written to
`macos/build/$(CONFIGURATION)/Ghostty.app` (`macos/build/Debug/Ghostty.app` by default).
The app uses `ghost halloween.icns` from the repository root as its default icon.
`make open` opens the existing bundle through macOS Launch Services; `make run`
runs its executable in the foreground. Neither launch target invokes Zig or
Xcode; both ask you to build first if the app is missing. Floating tabs are
enabled by default in the app, including direct and Finder launches.
Set `GHOSTTY_FLOATING_TABS_DISABLED=1` to explicitly disable them.
Use `make open GHOSTTY_FLOATING_TABS_DISABLED=1` or
`make run GHOSTTY_FLOATING_TABS_DISABLED=1` to opt out.
Quit an already-running instance before launching with a different flag.

`make install` copies the existing build to `~/Applications/Ghostty.app` without
rebuilding. Quit the installed app before reinstalling; installation replaces
the bundle's contents, removing stale files. Use `make install INSTALL_DIR=/Applications`
to install for all users if that directory is writable. `CONFIGURATION` selects
which build to install. The installed app also enables floating tabs by default.
`make open` still opens the build copy.

`make update` runs `git pull --ff-only origin main`, then `make app`, then
`make install`, stopping if any step fails. It updates the current branch without
switching branches, resetting local work, or creating a merge commit; divergent
history or conflicting local changes must be resolved manually. Quit the installed
app first. Command-line overrides such as `CONFIGURATION` and `INSTALL_DIR` are
passed through to the build and installation.

The defaults are `CONFIGURATION=Debug` and `OPTIMIZE=ReleaseFast`. Override
them on the command line, for example `make CONFIGURATION=ReleaseLocal`.
`make test` runs macOS unit tests, not UI tests.

This checkout requires Zig 0.16.0. The Makefile prefers the compatible toolchain
at `~/.local/bin/zig-aarch64-macos-0.16.0/zig`, falling back to `zig` on `PATH`.
`~/.local/bin/zig` is a symlink to that executable; its sibling `lib` directory
stays with the full toolchain. Use `make ZIG=/path/to/compatible/zig` to override.
The Homebrew Zig currently installed on this machine is 0.14.1 and cannot build
this checkout.

## Manual launch

Launch normally with floating tabs enabled:

```sh
macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty
```

To explicitly disable floating tabs for a fresh process:

```sh
GHOSTTY_FLOATING_TABS_DISABLED=1 macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty
```

Use `macos-titlebar-style = transparent` (the default) or `native`, with window
decorations enabled. Other titlebar styles and the Quick Terminal retain their
existing behavior. The flag is read when a terminal window is created; only the
value `1` disables floating tabs. Restart without it (or with `0`) to enable them
again. The old `GHOSTTY_EXPERIMENTAL_FLOATING_TABS` opt-in variable is no longer
used. There is no public configuration key yet.

The pill initially overlays the top-left of terminal content. Drag its header
to reposition it anywhere within the terminal area; it stays inside the window
when resized. The list opens upward near the bottom edge without moving the
header vertically. All tabs in a window share one pill position: dragging in
any tab updates the position for existing and new tabs. Separate windows have
independent positions and start at the top-left. Detached tabs keep the current
position independently; tabs moved into another group use that group's position.
Position is not saved across restarts.
Dragging moves only the pill, not the window or tab order.
Hover for 180 ms or click
to expand, select an existing tab, or use New Tab. Moving the pointer away
collapses it. Long titles truncate with a tooltip; larger tab groups scroll.
Press **Ctrl-T** from the terminal to open the manager with the current tab
highlighted. **Up/Down** move the highlight through the tabs and **New Tab**
without switching tabs; **Enter** activates the highlighted tab or creates a
new one. The list scrolls to keep the highlighted tab visible.
Hover over a tab row to reveal its small close button. **Delete** (also
forward delete / Fn-Delete) closes the keyboard-highlighted tab; it does
nothing on **New Tab**. Closing dismisses the manager and uses Ghostty's
normal tab-close action, including running-process confirmation and undo.
**Escape** or clicking outside dismisses it. Keyboard-opened lists stay open
when the pointer leaves; ordinary typing dismisses the list and goes to the
terminal. Ctrl-T is reserved for this manager while the experiment is enabled,
rather than being sent to the shell.

The existing keyboard commands, tab restoration, and split handling remain
authoritative. Drag reordering is intentionally omitted.

## Integration

`TerminalController` owns an overlay per window and removes it on close.
`FloatingTabModel` observes AppKit's tab group and window titles. Its items
are presentation snapshots, not a second tab lifecycle or persistence model.
Observer replacement is deferred outside KVO callbacks.

The overlay is a sibling above the existing terminal hosting view. It does not
participate in terminal constraints or intrinsic sizing, and empty areas pass
mouse events through. The command palette temporarily hides the overlay.

The native tab accessory is identified by Ghostty's existing identifier.
`NSTitlebarAccessoryViewController.isHidden` collapses it using public AppKit
API; no private tab-bar views are modified. AppKit's `isTabBarVisible` may
still report true because the native accessory remains installed. The window
hook also hides replacement accessories after grouping or fullscreen changes.
Native inline title editing falls back to the existing rename dialog.

## Verification

Build the prerequisite GhosttyKit framework with the repository's required Zig
version, then build and test the app:

```sh
zig build -Demit-macos-app=false -Dxcframework-target=native -Doptimize=ReleaseFast
macos/build.nu
macos/build.nu --action test
```

`FloatingTabModelTests` covers keyboard highlighting and activation, title updates, tab membership and selection,
detaching, stale selections, action delegation, and observer cleanup.
`FloatingTabOverlayTests` covers default enablement, explicit opt-out, unsupported
window styles, shared group positions, detach/merge, bounded dragging, upward expansion, resize,
geometry, keyboard dismissal and passthrough, pointer pass-through, command-palette
layering, and native accessory cleanup.
`GhosttyFloatingTabsUITests` covers Ctrl-T/arrow/Enter/Escape navigation, hover, tab actions, close confirmation,
dragging, typing, titles, splits, fullscreen, and the disabled path. `build.nu --action
test` skips UI tests. Run this suite in Xcode, or explicitly opt in for a
focused CLI run with `GHOSTTY_RUN_FLOATING_UI_TESTS=1` in the UI test runner's
environment.

For manual testing, check terminal typing immediately after selection, hover
without focus changes, unchanged terminal dimensions during expansion, tab
creation/closure and rename, merge/detach, restoration, native fullscreen,
command palette, split zoom, light/dark appearance, and a narrow window.
