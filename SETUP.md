# VocalLingo — Professional Setup Checklist

**Time required:** ~10 minutes end to end.
**No Terminal required.** Every step is inside Xcode.

---

## 1. Create the project in Xcode

1. Launch **Xcode 26**.
2. **File → New → Project…**
3. Platform: **iOS** → Application: **App** → Next.
4. Fill in:
   - **Product Name:** `VocalLingo`
   - **Team:** ABDI ALEX MOHIT (523MJL63MC)
   - **Organization Identifier:** `com.robertapolk`
     - Bundle Identifier will auto-fill as `com.robertapolk.VocalLingo`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - **Include Tests:** unchecked
5. Next → save to Desktop (or wherever you prefer) → Create.
6. Xcode opens the fresh project.

## 2. Sanity-run the empty template

1. Press **⌘R**. You should see a "Hello, world!" screen in the simulator.
2. Stop it (⌘.). This proves the project is valid before we touch it.

## 3. Delete the two template Swift files

In the project navigator (left sidebar), select these two files and press **Delete**, then **Move to Trash**:

- `ContentView.swift`
- `VocalLingoApp.swift` (the template one — we're replacing it with our own)

## 4. Add my Swift files

1. In Finder, open the `VocalLingo-Sources` folder I gave you.
2. Select **all 9 `.swift` files** (⌘A).
3. Drag them into the project navigator, dropping them onto the yellow **VocalLingo** group folder.
4. In the dialog that appears:
   - ✅ **Copy items if needed**
   - ✅ **Create groups** (not folder references)
   - ✅ **Add to targets: VocalLingo**
5. Click **Finish**.

Files added:
- `VocalLingoApp.swift` — @main SwiftUI App
- `AppDelegate.swift` — routes CarPlay scene role only
- `CarPlaySceneDelegate.swift` — CarPlay display handler
- `HomeView.swift` — main iPhone UI (4 language tabs)
- `PracticeView.swift` — phrase practice screen
- `UnitTestView.swift` — end-of-unit quiz
- `CurriculumData.swift` — 50 units × 4 languages
- `AppleIntelligence.swift` — FoundationModels wrapper
- `VoiceManager.swift` — AVSpeechSynthesizer wrapper

## 5. Configure Info.plist (via Xcode UI — not by editing files)

1. Click the blue **VocalLingo** project icon at the top of the navigator.
2. Under **TARGETS**, select **VocalLingo**.
3. Open the **Info** tab.
4. Under **Custom iOS Target Properties**, hover over any row → click the **+** button and add each of these keys:

| Key | Type | Value |
|---|---|---|
| `NSSpeechRecognitionUsageDescription` | String | `VocalLingo does not record your voice; this key is present only so Apple's speech synthesis frameworks can be linked safely.` |
| `ITSAppUsesNonExemptEncryption` | Boolean | `NO` |
| `UIBackgroundModes` | Array | one string item: `audio` |

**Do NOT add** `UIApplicationSceneManifest` manually — SwiftUI handles that. The CarPlay scene is added below via Capabilities.

## 6. Add Background Modes → Audio (via Capabilities)

1. Same project settings screen → **Signing & Capabilities** tab.
2. Click **+ Capability**.
3. Double-click **Background Modes**.
4. In the newly added row, check **☑ Audio, AirPlay, and Picture in Picture**.

## 7. Add CarPlay capability

1. Same tab → **+ Capability**.
2. Double-click **CarPlay Audio**.
3. You'll see a red X or warning because Apple hasn't approved your CarPlay entitlement yet. **That is expected and does not block simulator builds.**

## 8. Add the CarPlay scene manifest

The scene manifest can't be added through pure Capabilities UI for CarPlay. Do this:

1. **Info** tab (same target).
2. Under **Custom iOS Target Properties**, add key `UIApplicationSceneManifest` (Dictionary).
3. Inside it, add key `UISceneConfigurations` (Dictionary).
4. Inside **that**, add key `CPTemplateApplicationSceneSessionRoleApplication` (Array).
5. Add one Dictionary item to that array with:
   - `UISceneConfigurationName` = `CarPlay Configuration` (String)
   - `UISceneDelegateClassName` = `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate` (String)

**Do NOT add** `UIWindowSceneSessionRoleApplication` — SwiftUI's WindowGroup owns that.

## 9. Deployment target

1. **General** tab → **Minimum Deployments** → **iOS 17.0** (or 18.0 if you prefer — FoundationModels needs 18.1+ for real inference, but the app runs on 17 with the fallback path).

## 10. Build & run

1. Select **iPhone 15 Pro** simulator (or any iOS 17+ sim).
2. ⌘R.
3. App launches → HomeView with four language tabs.

## 11. Test CarPlay in the simulator (optional, no Apple approval needed)

With the simulator running:
1. **Xcode → Debug → Simulate External Displays → CarPlay**
2. A second window opens showing your CarPlay UI.

## 12. Icon (before TestFlight, not before running)

Drop a 1024×1024 PNG into `Assets.xcassets → AppIcon` slot. Xcode 15+ auto-generates all sizes from it.

---

## When Apple approves CarPlay Audio (3–10 business days)

1. Xcode → **Signing & Capabilities** tab.
2. The CarPlay row will still show the red X until you refresh provisioning.
3. Click **Try Again** on the CarPlay row, or delete and re-add the capability.
4. The X clears.

You can now archive and upload to TestFlight.

---

## Why this approach

Xcode owns the project format. It changes every release, has undocumented behaviors, and every corner case is only fully known by Xcode itself. Any hand-written `project.pbxproj` will eventually hit a case Xcode doesn't like. Creating the project through Xcode's own template guarantees it's valid and matches whatever your current Xcode version expects.

The Swift files are the actual product. Those are portable and stable. Xcode handles the wiring.
