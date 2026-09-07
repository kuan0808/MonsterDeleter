import Foundation
import Testing

@testable import MonsterDeleterKit

/// The matching rule of the accessibility tier, exercised the way `FinderIconReader` uses it:
/// the targets of a summon are keyed once, and each element of Finder's tree looks itself up.
@Suite("Icon identity")
struct IconIdentityTests {
  let target = URL(fileURLWithPath: "/Users/example/Documents/report.pdf")

  /// The target one element resolves to among a selection, or `nil` when it resolves to none.
  func resolved(_ element: IconIdentity, among targets: [URL]) -> URL? {
    element.lookupKey.flatMap { IconIdentity.index(targets)[$0] }
  }

  @Test("a URL that agrees is the target")
  func urlAgrees() {
    #expect(resolved(IconIdentity(url: target, name: nil), among: [target]) == target)
  }

  @Test("a URL that disagrees rules the element out even when the name matches")
  func urlOutranksTheName() {
    let elsewhere = URL(fileURLWithPath: "/Users/example/Desktop/report.pdf")
    #expect(resolved(IconIdentity(url: elsewhere, name: "report.pdf"), among: [target]) == nil)
  }

  @Test("a folder's URL matches with or without its trailing slash")
  func folderTrailingSlash() {
    let folder = URL(fileURLWithPath: "/Users/example/Documents/Invoices")
    let slashed = IconIdentity(url: URL(string: "file:///Users/example/Documents/Invoices/")!, name: nil)
    #expect(resolved(slashed, among: [folder]) == folder)
  }

  @Test("the same file reached through two spellings of its path is one file")
  func standardizedPaths() {
    let detour = URL(fileURLWithPath: "/Users/example/Desktop/../Documents/report.pdf")
    #expect(resolved(IconIdentity(url: detour, name: nil), among: [target]) == target)
  }

  @Test("without a URL the displayed name decides")
  func nameDecides() {
    #expect(resolved(IconIdentity(url: nil, name: "report.pdf"), among: [target]) == target)
  }

  @Test("without a URL a name with the extension hidden still matches")
  func hiddenExtension() {
    #expect(resolved(IconIdentity(url: nil, name: "report"), among: [target]) == target)
  }

  @Test("a name belonging to another file does not match")
  func differentName() {
    #expect(resolved(IconIdentity(url: nil, name: "invoice.pdf"), among: [target]) == nil)
  }

  @Test("an element that says nothing about itself is never the target")
  func nothingToGoOn() {
    #expect(IconIdentity(url: nil, name: nil).lookupKey == nil)
    #expect(IconIdentity(url: nil, name: "").lookupKey == nil)
    #expect(resolved(IconIdentity(url: nil, name: nil), among: [target]) == nil)
  }

  @Test("a bare stem never matches a file whose own name carries no extension")
  func stemDoesNotMatchAcrossFiles() {
    let readme = URL(fileURLWithPath: "/Users/example/Documents/README")
    #expect(resolved(IconIdentity(url: nil, name: "README.md"), among: [readme]) == nil)
  }

  @Test("a URL keeps two targets of one name apart where the displayed name cannot")
  func namesakesAreToldApartByURL() {
    let namesake = URL(fileURLWithPath: "/Users/example/Desktop/report.pdf")
    let selection = [target, namesake]
    #expect(resolved(IconIdentity(url: namesake, name: "report.pdf"), among: selection) == namesake)
    #expect(resolved(IconIdentity(url: target, name: nil), among: selection) == target)
  }

  @Test("a name two targets of the selection answer to resolves to neither of them")
  func ambiguousNameResolvesToNothing() {
    let folder = URL(fileURLWithPath: "/tmp/Report")
    let document = URL(fileURLWithPath: "/tmp/Report.pdf")
    let selection = [folder, document]
    #expect(
      resolved(IconIdentity(url: nil, name: "Report"), among: selection) == nil,
      "\"Report\" is the folder and the document with its extension hidden"
    )
    #expect(
      resolved(IconIdentity(url: document, name: "Report"), among: selection) == document,
      "a URL is never ambiguous, so the element that carries one still resolves"
    )
    #expect(resolved(IconIdentity(url: nil, name: "Report.pdf"), among: selection) == document)
  }

  @Test("one target listed twice is not an ambiguity with itself")
  func repeatedTargetStillResolves() {
    let detour = URL(fileURLWithPath: "/Users/example/Documents/../Documents/report.pdf")
    #expect(resolved(IconIdentity(url: nil, name: "report"), among: [target, detour]) == target)
  }
}
