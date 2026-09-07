# Icon aiming reads Finder's selection, not Finder's tree

The accessibility tier of target acquisition has to answer "where is this
file's icon on screen" before a show starts, so its cost is paid in front of the user every time.
Walking Finder's accessibility tree looking for the file's name costs about two seconds on a
Mac with one Finder window open, because every attribute is a synchronous message to Finder and
a window holds hundreds of elements.

So `FinderIconReader` never searches for a name. It asks each container of the tree for its
selection (`AXSelectedChildren`, `AXSelectedRows`), stops descending at any container that
answers, and matches the selected elements against the targets by the URL each one exposes. That
is both faster and more correct: the selection the Services item was invoked on *is* Finder's
selection, so the elements it wants are exactly the ones Finder hands back.

## Consequences

- **The traversal order is part of the decision.** The four Finder views hide their selection at
  different depths: the desktop two levels below its own root, a column view six levels down and
  behind up to nine sibling columns. Breadth first costs 139 ms in column view; depth first costs
  142 ms on the desktop. Two rounds, depth 2 then depth 6, is the only order with no bad case
  (31 to 41 ms), so the reader runs the search twice with a growing depth limit.
- **A budget, not a promise.** `TargetAimResolver` races the whole resolution against
  `budget` (150 ms, about 60 ms past the slowest resolution captured: the app-side cost is 42 to
  91 ms, where the warm-client traversal table above is 31 to 41 ms) and abandons it by
  cancelling.
  The read is an unstructured task for that reason: a task group waits for every child it holds,
  so a cancelled read sitting inside a synchronous message to a wedged Finder would stretch the
  wait by the messaging timeout on top of the budget. A source that ignored cancellation would
  then keep running unheeded, which is why `IconRectSource` states the requirement, and why the
  reader checks for cancellation per selected element rather than once per container.
- **Identity never comes from position.** An element is the target when its `AXURL` matches, or,
  when Finder exposes no URL for it, when its displayed name matches with or without the
  extension. Two files of the same name in two windows therefore stay apart, and a wrong match
  cannot send the monster to somebody else's file. The targets are keyed by that rule once per
  read (`IconIdentity.index`), so a selection of hundreds costs one lookup per element rather
  than a scan of every target. A name two targets of one selection answer to - the folder
  `Report` and the file `Report.pdf` with its extension hidden - is filed under neither, so an
  element carrying only that name resolves to nothing and its target falls to the right-click
  rather than borrowing the other file's icon.
- **One screen per show.** The show draws in one screen's panel, so `TargetAimResolver` keeps
  only the icons on one screen - the right-click's, or the one holding the most - and lets the
  rest join the fan, exactly as a target it could not resolve at all does. A desktop selection
  spanning two displays would otherwise aim between them and leave the far icon's explosion off
  the panel altogether, since an icon's burst sits on its icon unclamped and the panel clips
  whatever runs past its edge. The screen frames are passed in by `AppDelegate`, which keeps the
  resolver pure and its tests free of a display.
- **Finder's tree shape is a dependency.** The roles the reader descends into and the two levels
  it looks below a selected element are Finder's shape as of macOS 26. A future Finder that moves
  its icons resolves nothing and every show falls back to the right-click, which is the tier
  below and the behaviour the app had before this.

## Why not the alternatives

- **AppleScript** (`tell application "Finder" to get position of selection`) needs the Automation
  permission, works in icon view only, and returns coordinates relative to the window container.
- **Asking Finder for one element at a time by name** is the tree walk in another shape and costs
  the same messages.
- **Reading the tree on the main thread** would hold up the run loop the show is about to draw
  in; the read is `@concurrent` for that reason.
