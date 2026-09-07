import AppKit
import SwiftUI

/// The app window once the introduction is done: the three-step reminder, the way into a demo, the
/// settings and the guide, and - quietly, after each ring - the offer of icon aiming to someone
/// who has watched a whole selection explode in one.
public struct HomeView: View {
  private let onboarding: Onboarding
  private let iconAiming: IconAiming
  private let playDemo: () -> Void

  @State private var showsGuide = false

  public init(onboarding: Onboarding, iconAiming: IconAiming, playDemo: @escaping () -> Void) {
    self.onboarding = onboarding
    self.iconAiming = iconAiming
    self.playDemo = playDemo
  }

  public var body: some View {
    VStack(spacing: 18) {
      VStack(spacing: 8) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .scaledToFit()
          .frame(height: 64)
          .accessibilityHidden(true)
        Text("MonsterDeleter")
          .font(.system(size: 19, weight: .semibold))
        Text("It lives in the menu bar and stays out of the way until you feed it something.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      ServicesMenuArt(.trail)

      if showsAimingTip {
        aimingTip
      }

      HStack(spacing: 8) {
        Button("Play a Demo", action: playDemo)
          .keyboardShortcut(.defaultAction)
        SettingsLink { Text("Settings…") }
        Button("Guide") { showsGuide = true }
      }

      Button("Show the introduction again") { onboarding.restart() }
        .buttonStyle(.link)
        .font(.callout)
    }
    .padding(24)
    .frame(width: 460)
    .task {
      await iconAiming.watchTrust()
    }
    .sheet(isPresented: $showsGuide) {
      GuideView { showsGuide = false }
    }
  }

  /// Shown only to someone the ring fallback has actually happened to, and only until aiming is
  /// actually in effect - the wish and the grant, not the wish alone - or they dismiss it.
  private var showsAimingTip: Bool { onboarding.sawUnaimedFan && !iconAiming.isActive }

  private var aimingTip: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "scope")
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("Those explosions landed in a ring because MonsterDeleter cannot see where the icons are.")
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        SettingsLink { Text("Aim at each file's icon…") }
          .buttonStyle(.link)
          .font(.callout)
      }
      Spacer(minLength: 4)
      Button("Dismiss") { onboarding.dismissAimingTip() }
        .controlSize(.small)
    }
    .padding(12)
    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
  }
}
