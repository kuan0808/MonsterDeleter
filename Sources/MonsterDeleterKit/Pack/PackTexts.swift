/// The lines shown during the ask phase.
public struct PackTexts: Codable, Sendable, Hashable {
  /// The token in `bubbleMany` that the selection's count replaces.
  public static let countToken = "{count}"

  /// The question in the speech bubble for one item.
  public var bubble: String
  /// The question for a selection of more than one item; `{count}` is replaced by the count.
  public var bubbleMany: String
  /// The plain confirmation button.
  public var confirm: String
  /// The second, emphatic confirmation button. Both buttons confirm, as in the original.
  public var alternate: String

  public init(bubble: String, bubbleMany: String, confirm: String, alternate: String) {
    self.bubble = bubble
    self.bubbleMany = bubbleMany
    self.confirm = confirm
    self.alternate = alternate
  }

  /// The bubble line for a selection of `count` items.
  public func bubble(count: Int) -> String {
    count == 1 ? bubble : bubbleMany.replacingOccurrences(of: Self.countToken, with: String(count))
  }
}
