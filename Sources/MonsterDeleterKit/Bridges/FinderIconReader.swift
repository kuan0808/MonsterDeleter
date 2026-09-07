import AppKit
import ApplicationServices

/// Accessibility bridge: the accessibility tier of target acquisition (ADR-0005). It
/// reads Finder's window contents, and nothing else, while a show is being summoned, to find
/// where Finder draws each target's icon. SwiftUI has no accessibility-client API at all.
///
/// It asks each container of Finder's tree for its selection instead of searching the tree for
/// names. The Services selection is Finder's selection, so the selected elements are the
/// targets; a blind walk of Finder's tree costs about two seconds where this costs tens of
/// milliseconds (`docs/adr/0005-accessibility-target-tier.md`). The four places a target can be:
///
/// - icon view: `AXScrollArea > AXList`, whose selected children carry the name, the URL and a
///   64 pt icon on one `AXImage`,
/// - list view: `AXScrollArea > AXOutline`, whose selected rows hold `AXCell > AXTextField` for
///   the name and the URL, with the 16 pt `AXImage` beside it,
/// - column view: `AXBrowser`, one `AXScrollArea > AXList` per column, shaped like the list view,
/// - the desktop: a window whose own role is `AXScrollArea`, holding one `AXGroup` whose
///   selected children are `AXImage`s like the icon view's.
///
/// Nothing here throws or reports: a target it cannot resolve simply falls to the tier below.
public struct FinderIconReader: IconRectSource {
  /// How long one message to Finder may take. This is not what keeps the show waiting to a
  /// minimum - `TargetAimResolver.budget` is, and it abandons the read without waiting for it.
  /// This only stops a wedged Finder from holding a background thread for good, so it sits well
  /// above any healthy answer: a busy Finder answers in tens of milliseconds, and a timeout here
  /// silently prunes the branch it was reading, which costs the tier a target it could have had.
  private static let messagingTimeout: Float = 0.5
  /// How deep below a root the search for a container with a selection goes. The deepest of the
  /// four views is the column view, at six.
  private static let maxDepth = 6
  /// The first round's depth. The desktop keeps its selection two levels below its own root, so
  /// one shallow round finds it for a handful of messages instead of paying for a whole window
  /// first (`docs/adr/0005-accessibility-target-tier.md`).
  private static let shallowDepth = 2
  /// Roles worth descending into. Everything else in a Finder window is chrome.
  private static let containerRoles: Set<String> = [
    "AXWindow", "AXSplitGroup", "AXScrollArea", "AXBrowser", "AXList", "AXOutline", "AXGroup",
  ]
  /// How far below a selected element the name, the URL and the icon can sit: `AXRow > AXCell >
  /// AXTextField` in list view is the deepest.
  private static let itemDepth = 2

  public init() {}

  public func iconRects(for urls: [URL]) async -> [URL: CGRect] {
    guard !urls.isEmpty else { return [:] }
    let primaryScreenHeight = await MainActor.run { NSScreen.screens.first?.frame.maxY ?? 0 }
    return await Self.read(urls, primaryScreenHeight: primaryScreenHeight)
  }

  /// Off the main thread: every accessibility call is a synchronous message to Finder, and a
  /// busy Finder would otherwise hold up the run loop the show is about to draw in.
  @concurrent
  private static func read(_ urls: [URL], primaryScreenHeight: CGFloat) async -> [URL: CGRect] {
    guard AXIsProcessTrusted() else { return [:] }
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    else { return [:] }
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    AXUIElementSetMessagingTimeout(app, messagingTimeout)

    var found: [URL: CGRect] = [:]
    // The targets are keyed once, before the walk: a selection of hundreds would otherwise be
    // rescanned, and both paths standardized again, for every element Finder hands back.
    let targets = IconIdentity.index(urls)
    let roots = searchRoots(of: app)
    // Two rounds, the shallow one first. Everything a Finder window holds sits below everything
    // the desktop holds, so a single deep-first search would pay for a whole column view before
    // ever looking at the desktop, and a single breadth-first one would pay for every column of
    // that view. Within a round the search goes depth first and last child first: the column the
    // user right-clicked in is the rightmost one, and the focused window comes before the rest.
    for limit in [shallowDepth, maxDepth] where found.count < urls.count {
      var seen = Set<CFHashCode>()
      var stack = roots.filter { seen.insert(CFHash($0)).inserted }.map { (element: $0, depth: 0) }
      stack.reverse()
      while found.count < urls.count, !Task.isCancelled, let (element, depth) = stack.popLast() {
        guard depth <= limit else { continue }
        let values = attributes(
          element,
          of: [kAXRoleAttribute, kAXChildrenAttribute, "AXSelectedChildren", "AXSelectedRows"]
        )
        // A container that answers a selection query at all is the one holding the items, whether
        // or not anything in it is selected; there is no deeper container to look in. Both
        // queries count: an outline answers with rows where a list answers with children, and a
        // container that answers one of them with nothing has nothing to give.
        let selectedChildren = values[2] as? [AXUIElement]
        let selectedRows = values[3] as? [AXUIElement]
        if selectedChildren != nil || selectedRows != nil {
          for selected in (selectedChildren ?? []) + (selectedRows ?? []) {
            // Each of these elements costs its own messages to Finder, so a selection this size
            // is where an abandoned read has to notice it was abandoned.
            guard !Task.isCancelled else { return found }
            let candidate = candidate(selected, depth: itemDepth)
            guard let rect = candidate.icon ?? candidate.frame, !rect.isEmpty else { continue }
            guard let key = candidate.identity.lookupKey, let url = targets[key], found[url] == nil else { continue }
            found[url] = AccessibilityGeometry.appKitRect(rect, primaryScreenHeight: primaryScreenHeight)
          }
          continue
        }
        guard let role = values[0] as? String, containerRoles.contains(role) else { continue }
        for child in (values[1] as? [AXUIElement]) ?? [] where seen.insert(CFHash(child)).inserted {
          stack.append((child, depth + 1))
        }
      }
    }
    return found
  }

  /// Finder's focused window, then every window it has, the desktop among them.
  private static func searchRoots(of app: AXUIElement) -> [AXUIElement] {
    var roots: [AXUIElement] = []
    if let focused = attributes(app, of: ["AXFocusedWindow"])[0], CFGetTypeID(focused) == AXUIElementGetTypeID() {
      roots.append(focused as! AXUIElement)
    }
    roots += (attributes(app, of: [kAXWindowsAttribute])[0] as? [AXUIElement]) ?? []
    return roots
  }

  /// What one selected element of Finder's tree says about itself, gathered from the element and
  /// the two levels below it: the identity from wherever the URL and the name sit, the icon from
  /// the `AXImage` in the same place.
  private struct Candidate {
    var identity = IconIdentity(url: nil, name: nil)
    var icon: CGRect?
    var frame: CGRect?

    mutating func fillIn(from other: Candidate) {
      identity.url = identity.url ?? other.identity.url
      identity.name = identity.name ?? other.identity.name
      icon = icon ?? other.icon
    }
  }

  private static func candidate(_ element: AXUIElement, depth: Int) -> Candidate {
    let values = attributes(
      element,
      of: [kAXRoleAttribute, "AXURL", "AXFilename", kAXValueAttribute, "AXFrame", kAXChildrenAttribute]
    )
    var candidate = Candidate()
    candidate.identity = IconIdentity(
      url: (values[1] as? NSURL) as URL?,
      name: (values[2] as? String) ?? (values[3] as? String)
    )
    candidate.frame = rect(values[4])
    if values[0] as? String == "AXImage" {
      candidate.icon = candidate.frame
    }
    guard depth > 0 else { return candidate }
    for child in (values[5] as? [AXUIElement]) ?? [] {
      candidate.fillIn(from: Self.candidate(child, depth: depth - 1))
    }
    return candidate
  }

  /// Several attributes of one element in one message. Finder answers a message in well under a
  /// millisecond but charges for each one, so asking for six at once is what keeps a resolution
  /// inside its budget.
  private static func attributes(_ element: AXUIElement, of names: [String]) -> [AnyObject?] {
    var values: CFArray?
    guard
      AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(), &values)
        == .success,
      let array = values as? [AnyObject]
    else { return Array(repeating: nil, count: names.count) }
    // A missing attribute comes back as a null placeholder rather than a hole in the array.
    return array.map { $0 is NSNull ? nil : $0 }
  }

  private static func rect(_ value: AnyObject?) -> CGRect? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
    return rect
  }
}
