import AppKit
import MonsterDeleterKit

// A Services request can arrive the moment the run loop starts, including on a cold launch by
// pbs, so the provider is installed before SwiftUI calls NSApplication.run() (spike decision 1).
let servicesProvider = ServicesProvider()
NSApplication.shared.servicesProvider = servicesProvider
NSUpdateDynamicServices()

MenuBarApp.main()
