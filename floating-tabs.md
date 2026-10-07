# Ghostty Floating Tabs

## Goal

Add an experimental macOS floating tab manager to Ghostty.

Instead of showing the standard macOS tab bar permanently, show a small floating control near the **top-left corner** of the terminal.

Collapsed:

```text
┌──────────────────────────────────────────────────────────┐
│  ╭─ ● bpf-next ▾ ─╮                                     │
│  ╰────────────────╯                                     │
│                                                          │
│  $                                                       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

When the mouse hovers over the control, expand it to show all tabs:

```text
┌──────────────────────────────────────────────────────────┐
│  ╭──────────────────────╮                                │
│  │ ● bpf-next           │                                │
│  ├──────────────────────┤                                │
│  │   bpfsnoop           │                                │
│  │   linux              │                                │
│  │   vllm               │                                │
│  │   dgx-1              │                                │
│  │   dgx-2              │                                │
│  ├──────────────────────┤                                │
│  │ + New Tab            │                                │
│  ╰──────────────────────╯                                │
│                                                          │
│  $                                                       │
└──────────────────────────────────────────────────────────┘
```

The expanded UI must **overlay the terminal**. It must not resize or reflow the terminal surface.

## Design Principles

Keep this feature isolated from Ghostty internals as much as possible.

Prefer:

```text
new Swift files
        ↓
small integration point
        ↓
existing Ghostty tab/window infrastructure
```

Avoid:

```text
rewriting tab management
modifying libghostty
changing terminal surface behavior
duplicating Ghostty tab lifecycle logic
patching Apple's private tab-bar views
```

In particular, do not introduce a new tab model initially.

Use Ghostty's existing macOS tab/window model as the source of truth.

The floating UI is only an alternative presentation/controller for existing tabs.

## Architecture

Target architecture:

```text
TerminalController
      │
      │ existing tab/window management
      ▼
NSWindowTabGroup
      │
      ├── NSWindow
      ├── NSWindow
      ├── NSWindow
      └── NSWindow
             │
             ▼
        TerminalView
             │
             ▼
       Ghostty Surface


NEW:

FloatingTabOverlay
      │
      ├── reads tabGroup.windows
      ├── reads selectedWindow
      ├── displays current title
      ├── displays all tabs on hover
      └── selects existing windows
```

`NSWindowTabGroup` remains authoritative.

Do not maintain a second `[Tab]` array unless there is no reasonable alternative.

## File Organization

Prefer adding new files under the macOS terminal feature.

For example:

```text
macos/Sources/Features/Terminal/
├── TerminalController.swift
├── ...
└── FloatingTabs/
    ├── FloatingTabOverlay.swift
    ├── FloatingTabView.swift
    ├── FloatingTabModel.swift
    └── FloatingTabStyle.swift
```

Exact naming may be adjusted to match existing Ghostty conventions.

### FloatingTabOverlay.swift

Responsible for integrating the floating SwiftUI view with the existing terminal window.

It should:

- install the overlay
- position it at the top-left
- keep it above terminal content
- remove/clean it up with the window
- avoid changing terminal layout
- bridge the relevant `NSWindow` / `NSWindowTabGroup` state into SwiftUI

Prefer keeping AppKit-specific integration here.

### FloatingTabView.swift

Pure UI where practical.

Responsibilities:

- collapsed pill
- expanded tab list
- hover detection
- tab selection
- new-tab action
- optional close action
- visual transitions

Keep Ghostty-specific logic out of this file where possible.

Conceptually:

```swift
struct FloatingTabView: View {
    @ObservedObject var model: FloatingTabModel

    @State private var hovering = false

    var body: some View {
        ...
    }
}
```

### FloatingTabModel.swift

Thin adapter around existing Ghostty/AppKit state.

Possible exposed state:

```swift
struct FloatingTabItem: Identifiable {
    let id: ObjectIdentifier
    let title: String
    let selected: Bool
}
```

The model should derive these items from:

```swift
window.tabGroup?.windows
window.tabGroup?.selectedWindow
```

Possible operations:

```swift
select(_ tab: FloatingTabItem)
close(_ tab: FloatingTabItem)
newTab()
```

These operations should call existing Ghostty/AppKit mechanisms rather than reproduce tab lifecycle logic.

### FloatingTabStyle.swift

Keep appearance constants separate from behavior.

Examples:

```swift
enum FloatingTabStyle {
    static let cornerRadius: CGFloat = ...
    static let collapsedHeight: CGFloat = ...
    static let horizontalPadding: CGFloat = ...
    static let topInset: CGFloat = ...
    static let leadingInset: CGFloat = ...
}
```

Use native macOS materials where appropriate.

Avoid a large amount of hard-coded styling in `FloatingTabView`.

## Existing Code Changes

Keep modifications to existing Ghostty files small.

The desired shape is roughly:

```swift
if floatingTabsEnabled {
    installFloatingTabOverlay()
}
```

rather than putting the implementation directly into `TerminalController.swift`.

If configuration integration requires touching existing enums/switches, make only the minimum required changes.

Ideally the diff looks approximately like:

```text
existing files:
    +20–50 lines

new files:
    majority of implementation
```

This is a preference, not a hard numerical requirement.

Do not contort the architecture simply to satisfy a line-count target.

## Initial Configuration

For the first prototype, it is acceptable to gate the feature with an internal/experimental condition if adding a public configuration option requires broad changes.

Once the prototype works, prefer exposing something conceptually equivalent to:

```text
macos-titlebar-style = floating-tabs
```

or another configuration option consistent with Ghostty's existing configuration architecture.

Do not unnecessarily change the semantics of existing titlebar styles.

## Native Tab Bar

When floating tabs are enabled, hide the standard macOS tab bar.

Do not attempt to heavily restyle Apple's native tab bar.

The desired model is:

```text
NSWindowTabGroup
    ↑
still used internally

native tab UI
    ↓
hidden

FloatingTabView
    ↓
custom presentation
```

Preserve native tab grouping/lifecycle behavior wherever possible.

## Placement

The floating control should appear near the top-left of the terminal/window.

Conceptually:

```text
╭──────────────────────────────────────────────╮
│ ● ● ●    ╭─ bpf-next ▾ ─╮                  │
│          ╰───────────────╯                  │
├──────────────────────────────────────────────┤
│                                              │
│ terminal                                     │
```

or, depending on the existing Ghostty window hierarchy:

```text
╭──────────────────────────────────────────────╮
│ ╭─ bpf-next ▾ ─╮                            │
│ ╰───────────────╯                            │
│                                              │
│ terminal                                     │
```

Choose whichever integrates most naturally with Ghostty's existing titlebar/window implementation.

Important requirement:

**Do not reduce the terminal surface size merely to make room for the expanded tab list.**

The expanded list should float over terminal content.

## Collapsed State

Normally display only the active tab.

Example:

```text
╭─ ● bpf-next ▾ ─╮
```

Desired characteristics:

- compact
- visually quiet
- current tab title visible
- obvious enough that it can be discovered
- doesn't distract from terminal contents

Optional later enhancement:

```text
not nearby       reduced opacity
mouse nearby     increased opacity
hover            fully visible + expanded
```

Do not make opacity behavior part of the first implementation unless trivial.

## Expanded State

Hovering over the pill expands it vertically.

Example:

```text
╭──────────────────────╮
│ ● bpf-next           │
├──────────────────────┤
│   bpfsnoop           │
│   linux              │
│   vllm               │
│   dgx-1              │
│   dgx-2              │
├──────────────────────┤
│ + New Tab            │
╰──────────────────────╯
```

Requirements:

- show all tabs in the current tab group
- clearly indicate selected tab
- clicking a tab activates it
- expansion overlays terminal content
- leaving the component collapses it

Use a small delay before expansion if necessary to prevent accidental activation while the cursor passes through the area.

A reasonable starting point is approximately 150–250 ms.

Do not hard-code complicated timer behavior until basic hover works correctly.

## Tab Titles

Use the same title Ghostty/native tabs currently expose.

Do not invent a separate naming mechanism.

Shell-driven title changes should eventually propagate automatically to the floating tab manager.

If observing title changes is difficult, start with refresh-on-tab-state-change and document the limitation.

## Selecting Tabs

Selecting an entry should activate the corresponding existing window/tab.

Prefer existing AppKit/Ghostty APIs.

Conceptually this may involve:

```swift
tabWindow.makeKey()
```

or selecting the corresponding window through `NSWindowTabGroup`.

Inspect the existing Ghostty implementation and use the same mechanism Ghostty already uses for `goto_tab` or equivalent functionality.

Do not assume `makeKey()` alone is correct without checking existing code.

## Creating Tabs

The `+ New Tab` action should invoke Ghostty's existing new-tab action.

Do not manually construct a terminal window/surface from the floating UI.

Conceptually:

```text
FloatingTabView
      ↓
existing Ghostty new-tab command
      ↓
TerminalController / app
      ↓
existing tab creation
```

## Closing Tabs

Closing tabs is useful but not required for the first prototype.

If implemented, reuse Ghostty's existing close-tab/window path.

Do not directly destroy Ghostty terminal surfaces from `FloatingTabView`.

## Reordering

Do not implement custom tab reordering in v1.

First make these reliable:

```text
display
hover
select
new tab
close (optional)
```

Reordering can come later.

If reordering is eventually implemented, update the underlying `NSWindowTabGroup` ordering rather than maintaining a UI-only ordering.

## Keyboard Behavior

Existing Ghostty shortcuts must continue working:

```text
⌘T
⌘W
⌘1 ... ⌘9
next tab
previous tab
```

The floating UI must reflect changes caused by keyboard commands.

The UI is a view/controller over Ghostty state, not the owner of that state.

## Focus

Be careful not to steal keyboard focus from the terminal merely because the mouse enters the floating tab manager.

Hovering should not change terminal focus.

Clicking a tab obviously changes the active tab/window.

After tab selection, terminal input should behave normally without requiring an extra click.

## Window Events

The floating UI needs to remain synchronized when:

- a tab is created
- a tab closes
- selected tab changes
- tab title changes
- tab moves between windows
- tab group changes
- a window is restored
- a window enters/exits fullscreen

Prefer observing existing state/events rather than polling.

If reliable observation is complicated, use the simplest existing Ghostty notification mechanism first.

## Fullscreen

Do not let fullscreen support block the initial prototype.

However:

- it must not crash
- it must not corrupt tab state
- the overlay should either work or intentionally hide itself

Document any initial fullscreen limitation.

## Splits

Splits and tabs are separate concepts.

Do not make the floating tab UI aware of Ghostty splits unless required for obtaining the tab title.

Example:

```text
Tab: linux

┌─────────────────┬─────────────────┐
│ vim             │ make -j32       │
│                 │                 │
└─────────────────┴─────────────────┘
```

The floating manager still shows one `linux` tab.

Leave split management untouched.

## Animation

Use restrained native animation.

Desired feeling:

```text
collapsed pill
      ↓ hover
slight width/height transition
      ↓
tab list
```

Avoid flashy animation.

Terminal interaction should feel immediate.

Respect macOS Reduce Motion if SwiftUI/native animation APIs do not already handle it appropriately.

## Appearance

Aim for something that feels native to Ghostty/macOS rather than a web-style dropdown.

Potential building blocks:

```swift
.material
.ultraThinMaterial
NSVisualEffectView
RoundedRectangle
```

Use Ghostty's existing colors/configuration where appropriate.

Support light/dark mode automatically.

Do not introduce a separate theme system.

## Performance

The floating tab manager should be effectively free compared with terminal rendering.

Avoid:

- polling
- repeated reconstruction of terminal state
- expensive animations
- timers running while collapsed
- touching terminal rendering code

The tab count will normally be small, so simple SwiftUI rendering is sufficient.

## Implementation Sequence

### Phase 1 — Static prototype

Create the floating overlay with hard-coded sample tabs.

Verify:

```text
window placement
overlay behavior
hover expansion
visual design
terminal remains usable underneath
```

No Ghostty tab integration yet.

### Phase 2 — Read existing tabs

Replace sample data with:

```swift
window.tabGroup?.windows
window.tabGroup?.selectedWindow
```

Show actual titles and selected state.

### Phase 3 — Tab switching

Wire clicks to Ghostty's existing tab-selection mechanism.

Verify:

```text
mouse selection
⌘1...⌘9
next/previous tab
```

all stay synchronized.

### Phase 4 — Hide native tab bar

Only after custom tab switching works reliably, hide the native macOS tab UI.

This makes debugging much easier.

### Phase 5 — New tab

Wire `+ New Tab` to Ghostty's existing action.

### Phase 6 — Lifecycle synchronization

Handle:

```text
create
close
rename/title change
move
restore
fullscreen
```

### Phase 7 — Polish

Add:

```text
hover delay
native material
subtle animation
optional close buttons
long-title truncation
large-tab-list scrolling
```

## Non-Goals for v1

Do NOT implement:

- a new terminal engine
- changes to libghostty
- a new tab persistence system
- a new tab lifecycle model
- tab groups/workspaces
- session restoration replacement
- split management
- drag-and-drop tab reordering
- sidebar mode
- custom shell integration
- Linux support

Keep the experiment narrowly focused on:

> Replace the visible macOS tab UI with a compact floating tab manager while preserving Ghostty's existing terminal and tab infrastructure.

## Upstream-Friendly Changes

Even though this may initially live in a fork, structure the work so it could plausibly become an upstream feature later.

That means:

- new files for the feature
- small integration points
- no unrelated formatting changes
- no refactoring merely for aesthetics
- no changes to libghostty
- reuse existing actions/state
- keep existing behavior unchanged when floating tabs are disabled

Ideally:

```text
floating tabs OFF
        ↓
behavior identical to upstream Ghostty

floating tabs ON
        ↓
native tab presentation hidden
        ↓
FloatingTabOverlay active
```

## First Task for Codex

Before editing anything, inspect the current Ghostty macOS implementation and identify:

1. Where `TerminalController` creates/configures the terminal window.
2. Where `TerminalView` is attached.
3. How Ghostty creates a new tab.
4. How Ghostty selects next/previous/specific tabs.
5. How `NSWindowTabGroup` is currently used.
6. How the native tab bar is shown/hidden.
7. How tab titles are updated.
8. Which existing notification/state mechanisms can update a custom view.

Then propose the **smallest integration point** for `FloatingTabOverlay`.

Do not begin by refactoring `TerminalController`.

After identifying the integration point, implement Phase 1 and Phase 2 using new files wherever practical.

Keep existing-file modifications minimal and explain every existing-file modification before making it.
