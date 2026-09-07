import SwiftUI
import UniformTypeIdentifiers

/// The Settings window, on ⌘, where macOS keeps preferences: everything switchable in one place -
/// the character and where new ones come from, where the monster aims, and the sound. Three short
/// sections fit one pane, so nothing is hidden behind a tab.
public struct SettingsView: View {
  private let library: PackLibrary
  private let iconAiming: IconAiming
  private let sound: ShowSound

  @State private var previews = PackPreviews()
  @State private var isChoosingFile = false
  @State private var isInstalling = false
  @State private var outcomes: [InstallOutcome] = []
  @State private var isTargeted = false

  public init(library: PackLibrary, iconAiming: IconAiming, sound: ShowSound) {
    self.library = library
    self.iconAiming = iconAiming
    self.sound = sound
  }

  public var body: some View {
    Form {
      Section("Character") {
        characters
        dropZone
        ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
          Label(outcome.message, systemImage: outcome.isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(outcome.isFailure ? Color.red : Color.green)
            .font(.callout)
            .accessibilityLabel(outcome.message)
        }
      }

      Section("Where the monster aims") {
        aiming
      }

      Section("Sound") {
        Toggle(isOn: soundBinding) {
          Text("Play the show's sound")
          Text("The music, the monster's voice and the explosion.")
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
    .task {
      await previews.load(library.entries, from: library)
    }
    // The grant, re-read while this window is open: the user can give it or take it away in System
    // Settings without the app noticing otherwise, and nobody should have to relaunch.
    .task {
      await iconAiming.watchTrust()
    }
    .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.zip], allowsMultipleSelection: true) {
      if case .success(let urls) = $0 {
        install(urls)
      }
    }
  }

  // MARK: Character

  @ViewBuilder
  private var characters: some View {
    if library.entries.isEmpty {
      Label("No characters are installed. Drop one below to play a show.", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
        .font(.callout)
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(library.entries) { entry in
            characterButton(entry)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  func characterButton(_ entry: PackEntry) -> some View {
    let isCurrent = entry.id == library.currentID
    let name = library.isCurrent(entry.id) ? library.currentEntry?.name ?? entry.name : entry.name
    return Button {
      library.select(entry.id)
    } label: {
      VStack(spacing: 4) {
        Group {
          if let frame = previews.frames[entry.id] {
            Image(decorative: frame, scale: 2).resizable().scaledToFit()
          } else {
            Image(systemName: "person.crop.square.badge.camera")
              .font(.system(size: 20))
              .foregroundStyle(.tertiary)
          }
        }
        .frame(width: 56, height: 52)
        Text(name)
          .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
          .lineLimit(1)
      }
      .frame(width: 76)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(isCurrent ? Color.accentColor : .clear)
      )
    }
    .buttonStyle(.plain)
    .disabled(isInstalling)
    .accessibilityLabel(name)
    .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
  }

  private var dropZone: some View {
    HStack(spacing: 12) {
      Image(systemName: "shippingbox")
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text("Add a character")
        Text("Drop a .zip someone sent you here.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Choose Zip…") { isChoosingFile = true }
        .disabled(isInstalling)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .strokeBorder(
          isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
          style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
    )
    .dropDestination(for: URL.self) { urls, _ in
      install(urls)
      return true
    } isTargeted: {
      isTargeted = $0
    }
  }

  // MARK: Aiming

  private var aiming: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(isOn: aimingBinding) {
        Text("Aim at each file's icon")
        Text("On, every item explodes on its own icon. Off, the explosions gather where you right-clicked.")
      }
      AimingArt()
        .frame(maxWidth: .infinity, alignment: .leading)
      if iconAiming.isRequestingPermission || iconAiming.isWaitingForAnswer {
        Label(
          iconAiming.isWaitingForAnswer ? "Waiting for your answer in macOS…" : "Waiting for macOS…",
          systemImage: "hourglass"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      } else if iconAiming.needsPermission {
        // The switch above reads off because that is the truth, so this says what is missing
        // rather than contradicting it. macOS shows its own prompt once per app, so the pane is
        // the way back to it, and withdrawing the request is the way out of this row.
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(
              """
              Accessibility permission is off. The monster still keeps \
              aiming where you right-clicked.
              """
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
              Button("Open Accessibility Settings…") { iconAiming.openAccessibilitySettings() }
                .controlSize(.small)
              Button("Stop Asking") { iconAiming.setEnabled(false) }
                .controlSize(.small)
            }
          }
        }
      }
    }
  }

  // MARK: Bindings and actions

  /// The switch shows the effective state, not the wish: with the permission missing it reads off,
  /// and it turns itself on the moment the grant arrives because the wish was remembered.
  private var aimingBinding: Binding<Bool> {
    Binding(get: { iconAiming.isActive }, set: { iconAiming.setEnabled($0) })
  }

  private var soundBinding: Binding<Bool> {
    Binding(get: { sound.isEnabled }, set: { sound.setEnabled($0) })
  }

  /// Installs each dropped file in turn and shows one line per file, in drop order.
  private func install(_ urls: [URL]) {
    guard !isInstalling else { return }
    isInstalling = true
    outcomes = []
    Task {
      defer { isInstalling = false }
      var installed: Set<PackEntry.ID> = []
      outcomes = await InstallOutcome.outcomes(for: urls) {
        let installation = try await library.install(zipAt: $0)
        installed.insert(installation.entry.id)
        return installation
      } isCurrent: {
        library.isCurrent($0)
      } wearing: {
        await library.currentPack()?.descriptor.name
      }
      await previews.load(library.entries, from: library, reloading: installed)
    }
  }
}
