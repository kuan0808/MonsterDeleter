import AppKit
import SwiftUI

/// The introduction, in the app's own window on first launch: what it does, how to summon it from
/// Finder, and the one permission worth offering. Three screens, each a picture with a caption
/// under it, each skippable, and the Finder one carries the whole weight - a user who cannot find
/// **Services > Feed to Monster** has no product at all.
public struct OnboardingView: View {
  private let library: PackLibrary
  private let onboarding: Onboarding
  private let iconAiming: IconAiming
  private let playDemo: () -> Void

  @State private var step = 0
  @State private var monster: CGImage?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let lastStep = 2

  /// The window's width, and the padding around everything in it.
  static let width: CGFloat = 460
  private static let padding: CGFloat = 24
  /// What a step has to draw in, once the padding is off.
  static var stepWidth: CGFloat { width - padding * 2 }

  /// The height every step is given, which is the height of the TALLEST state any step can reach:
  /// the third one while the permission is missing - the aiming picture (111), the two-line warning
  /// and its controls under it (12 + 28 + 6 + 20), then the title (14 + 23) and the three-line caption
  /// (14 + 60). The window is sized from its content (`.windowResizability(.contentSize)`) and does
  /// not grow when the step changes, so a step taller than this one is drawn straight through the
  /// controls under it. Any copy change here has to be measured again - `OnboardingLayoutTests`
  /// fails when a step outgrows this number.
  static let stepHeight: CGFloat = 288

  public init(
    library: PackLibrary,
    onboarding: Onboarding,
    iconAiming: IconAiming,
    playDemo: @escaping () -> Void
  ) {
    self.library = library
    self.onboarding = onboarding
    self.iconAiming = iconAiming
    self.playDemo = playDemo
  }

  public var body: some View {
    VStack(spacing: 18) {
      Group {
        switch step {
        case 0: whatItDoes
        case 1: findItInFinder
        default: aimAtIcons
        }
      }
      .frame(maxWidth: .infinity, minHeight: Self.stepHeight, alignment: .top)
      controls
    }
    .padding(Self.padding)
    .frame(width: Self.width)
    .task {
      monster = await library.currentPack()?.frames(for: .point).first
    }
  }

  // MARK: Steps
  // Not private, so `OnboardingLayoutTests` can lay each one out on its own and measure what it
  // needs against `stepHeight`.

  var whatItDoes: some View {
    step(
      title: "A monster eats the file",
      caption: """
        Point it at a file, a folder, or a whole selection. A monster walks in, asks, and kicks it \
        into the Trash. MonsterDeleter never deletes permanently.
        """
    ) {
      HStack(spacing: 14) {
        Image(systemName: "doc.fill")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.quaternary)
        monsterImage
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.quaternary)
        Image(systemName: "trash.fill")
          .font(.system(size: 38))
          .foregroundStyle(.secondary)
      }
      .frame(height: 112)
      .accessibilityHidden(true)
    }
  }

  /// The pack's own character where one has loaded, so the introduction shows the monster the user
  /// is about to meet rather than a stand-in; the app icon until it has.
  @ViewBuilder
  private var monsterImage: some View {
    if let monster {
      Image(decorative: monster, scale: 2)
        .resizable()
        .scaledToFit()
        .frame(height: 112)
    } else {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(height: 76)
    }
  }

  var findItInFinder: some View {
    step(
      title: "Find it in Finder",
      caption: "Right-click a file, a folder, or a whole selection. Services is the last item of the menu."
    ) {
      VStack(spacing: 6) {
        ServicesMenuArt()
        summonStatus
        Text("Missing? Keep MonsterDeleter running. Check System Settings > Keyboard > Keyboard Shortcuts > Services.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var summonStatus: some View {
    Label(
      onboarding.hasSummonedFromFinder ? "You have used it - that is all there is to it." : "Not used yet",
      systemImage: onboarding.hasSummonedFromFinder ? "checkmark.circle.fill" : "circle.dashed"
    )
    .font(.system(size: 11))
    .foregroundStyle(onboarding.hasSummonedFromFinder ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
  }

  var aimAtIcons: some View {
    step(
      title: "Aim at each file's icon",
      caption: """
        Let MonsterDeleter see where Finder draws your files and every item of a selection explodes \
        on its own icon. Without it the monster walks to the spot you right-clicked and the \
        explosions gather there - everything else works the same.
        """
    ) {
      VStack(spacing: 12) {
        AimingArt()
        permissionStatus
      }
      // A grant given in System Settings while this step is up shows here without a relaunch, and
      // the polling stops with the step.
      .task {
        await iconAiming.watchTrust()
      }
    }
  }

  @ViewBuilder
  private var permissionStatus: some View {
    if iconAiming.isRequestingPermission || iconAiming.isWaitingForAnswer {
      Label(
        iconAiming.isWaitingForAnswer ? "Waiting for your answer in macOS…" : "Waiting for macOS…",
        systemImage: "hourglass"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    } else if iconAiming.needsPermission {
      VStack(spacing: 6) {
        Text(
          """
          Accessibility permission is off. Until you grant it, the monster keeps aiming where \
          you right-clicked.
          """
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          Button("Open Accessibility Settings…") { iconAiming.openAccessibilitySettings() }
          Button("Stop Asking") { iconAiming.setEnabled(false) }
        }
        .controlSize(.small)
      }
    } else if iconAiming.isActive {
      Label("On", systemImage: "checkmark.circle.fill")
        .font(.system(size: 11))
        .foregroundStyle(Color.green)
    }
  }

  private func step(title: String, caption: String, @ViewBuilder art: () -> some View) -> some View {
    VStack(spacing: 14) {
      art()
      Text(title)
        .font(.system(size: 19, weight: .semibold))
      Text(caption)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: Controls

  private var controls: some View {
    HStack {
      Button(step == Self.lastStep ? "Not Now" : "Skip") { onboarding.complete() }
        .buttonStyle(.link)
        .keyboardShortcut(.cancelAction)
      Spacer()
      HStack(spacing: 6) {
        ForEach(0...Self.lastStep, id: \.self) { index in
          Circle()
            .fill(index == step ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            .frame(width: 6, height: 6)
        }
      }
      .accessibilityHidden(true)
      Spacer()
      HStack(spacing: 8) {
        if step == 1 {
          Button("Try a Demo", action: playDemo)
        }
        primaryButton
      }
    }
  }

  @ViewBuilder
  private var primaryButton: some View {
    if step < Self.lastStep {
      Button("Continue") { advance() }
        .keyboardShortcut(.defaultAction)
    } else if iconAiming.isEnabled {
      // The wish is set: either it is on, or the step is saying what macOS has not granted yet.
      Button("Done") { onboarding.complete() }
        .keyboardShortcut(.defaultAction)
    } else {
      // The switch is the request: macOS raises its own prompt, and the step then says where it
      // stands rather than leaving a permanent button behind.
      Button("Turn On") { iconAiming.setEnabled(true) }
        .keyboardShortcut(.defaultAction)
    }
  }

  private func advance() {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
      step = min(step + 1, Self.lastStep)
    }
  }
}
