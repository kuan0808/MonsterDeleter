import Foundation

/// What a person who has never seen this app needs to know, in the app itself: it is where someone
/// who has already installed it looks, and it works with no network. The README carries a short
/// version for people who have only found the source.
public enum Guide {
  public struct Entry: Sendable, Hashable, Identifiable {
    public let symbol: String
    public let question: String
    public let answer: String

    public var id: String { question }

    public init(symbol: String, question: String, answer: String) {
      self.symbol = symbol
      self.question = question
      self.answer = answer
    }
  }

  public static let entries: [Entry] = [
    Entry(
      symbol: "sparkles",
      question: "What happens when you feed it something",
      answer: """
        A monster walks in from the side of the screen, points at what you picked and asks. Answer \
        and it kicks the lot into an explosion. A whole selection is one show, with one explosion \
        per item.
        """
    ),
    Entry(
      symbol: "arrow.up.bin",
      question: "Where the files go",
      answer: """
        When you confirm, MonsterDeleter moves the selected items to the Trash and reports any \
        failures. It never deletes permanently. Finder handles restoration.
        """
    ),
    Entry(
      symbol: "escape",
      question: "Stopping a show",
      answer: """
        Press Esc, or click anywhere outside the buttons, while the monster is asking. Nothing is \
        touched until you answer.
        """
    ),
    Entry(
      symbol: "person.2",
      question: "Changing character",
      answer: """
        Pick one in Settings, or press the swap button beside the monster's question to change \
        character in the middle of a show.
        """
    ),
    Entry(
      symbol: "shippingbox",
      question: "Installing a character someone sent you",
      answer: """
        Drop the .zip on the Character section of Settings, or use Choose Zip. A character with the \
        same name replaces the one you have.
        """
    ),
    Entry(
      symbol: "scope",
      question: "Aiming at the file's icon",
      answer: """
        With the Accessibility permission, MonsterDeleter reads where Finder draws your files while \
        a show is being summoned - nothing else, nothing stored, nothing sent anywhere - and each \
        item explodes on its own icon. Decline and the monster aims at the spot you right-clicked \
        instead; everything else works the same.
        """
    ),
    Entry(
      symbol: "questionmark.folder",
      question: "If Feed to Monster is missing from Finder",
      answer: """
        The app has to be running: look for its icon in the menu bar. macOS also lets you switch \
        Services entries off in System Settings, under Keyboard > Keyboard Shortcuts > Services.
        """
    ),
    Entry(
      symbol: "speaker.slash",
      question: "Turning the sound off",
      answer: "Settings has one switch for the music, the voice and the explosion."
    ),
    Entry(
      symbol: "trash",
      question: "Uninstalling",
      answer: """
        Quit from the menu bar item, drag MonsterDeleter to the Trash, and delete the folder \
        ~/Library/Application Support/MonsterDeleter, which holds the characters you installed. The \
        Finder entry goes with the app.
        """
    ),
  ]
}
