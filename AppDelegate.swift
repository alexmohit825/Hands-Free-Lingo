import UIKit
import CarPlay

/// Application delegate — used only to route the CarPlay scene role.
///
/// Everything else (phone/iPad windows) is handled by SwiftUI's WindowGroup
/// via `@UIApplicationDelegateAdaptor` in `VocalLingoApp.swift`. We must NOT
/// override `application(_:configurationForConnecting:options:)` for the
/// phone case — iOS 26 will reject an arbitrary UISceneConfiguration name that
/// isn't declared in Info.plist. Instead, we implement the CarPlay routing on
/// a *separate* delegate method that fires only when the CarPlay scene tries
/// to connect: UIKit auto-reads Info.plist's Scene Configuration entry for
/// `CPTemplateApplicationSceneSessionRoleApplication` and instantiates
/// `CarPlaySceneDelegate` from the class name we put there.
///
/// So this file is effectively empty on purpose. The Info.plist wiring alone
/// is what makes CarPlay work.
public final class AppDelegate: NSObject, UIApplicationDelegate { }

// FILE COMPLETE
