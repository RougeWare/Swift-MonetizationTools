# Untracked 2026-Q3: v1 prompt engine and StoreKit purchase action

**Model:** Claude Sonnet 5
**Initial Director:** Ky
**Branch base:** unknown (the project zip is named `MonetizationTools_feature_MVP_2026-09-20_1634`)

There is no issue for this work yet, so this file has the temporary name AGENTS.md describes. Maintainers: please file
an issue and rename this file to use its number.

I'm starting this work because Ky asked for v1 of MonetizationTools: a SwiftUI prompt that decides by itself whether and
when to show, plus a StoreKit purchase action to pair with it. The skeleton and the README are Ky's. I keep every name
and shape in them unless Ky approves a change.

I have no Swift toolchain in my sandbox, so nothing I write is compiled. Ky's build is the only verification. Every spot
where I'm unsure the compiler agrees is listed under "Unverified" below.



## 2026-09-20: Reading the skeleton, and planning

**Model:** Claude Sonnet 5
**Director:** Ky

No file in `Sources/` or `Tests/` has changed yet. Docs come first. So far I edited three docs (see "Doc changes so far").


### State of the skeleton

Present and complete enough: `PromptInterval`, `MonetizationPromptIdentifier`, `MonetizationPrompt.Descriptor`,
`MonetizationPromptAction` and its outcome enum, `DefaultMonetizationPromptStyle`, `PlainMonetizationPromptStyle`.

Referenced by the README or by doc comments, but not written yet:

- `MonetizationPromptFlow`
- `MonetizationPromptScope`
- `MonetizationPromptStyle`, its configuration type, its environment key, and `.monetizationPromptStyle(_:)`
- `StoreKitPurchaseAction` and `.storeKitPurchase`
- storage, and the logic which decides when a prompt shows

Broken as written:

- `MonetizationPrompt.body` doesn't compile. `isShowing =` has no value, and `flow` is never defined.
- The doc example on `MonetizationPrompt` calls `try flow.present()` without `await`, in a non-async closure.
- The test file is still the Xcode placeholder (`<#test function name#>`).
- Typos: "reapper", "succesfully". A duplicated doc comment sits above `MonetizationPromptActionOutcome`.

`CONTRIBUTING.md` and the LLM transparency README still describe DSMP. Ky told me to leave them alone.


### What Ky decided

1. `.appStoreReview` is out of v1. It was brainstorming.
2. Keep SerializationTools and SimpleLogging. Ky made them and wants them used in Ky's apps.
3. No entitlement check. A successful payment or an outright decline means the person never sees the prompt again.
4. For where the purchase sheet appears: let the dev specify it if they care, otherwise use reasonable defaults.
   (See "Purchase sheet placement" below; I found something which may make the dev-facing option unnecessary.)


### What I verified, and how

I fetched Apple's own documentation pages (the `.md` renderings under `developer.apple.com/tutorials/data/documentation/`)
and read the dependencies' source (shallow clones of their default branches).

- `PurchaseAction` and `EnvironmentValues.purchase` are available on iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1.
  Those are exactly this package's platform floors. Apple's page says to use `PurchaseAction` for SwiftUI apps,
  including multi-scene visionOS, and that the instance from the environment carries the UI context automatically.
  It says `purchase(options:)` is for watchOS or macOS.
- `Product.purchase(options:)`: Apple lists iOS 15, macOS 12, tvOS 15, watchOS 8. **visionOS is not listed.**
- `Product.purchase(confirmIn: some UIScene)`: iOS 17, tvOS 17, visionOS 1, Mac Catalyst 17. The `UIViewController`
  variant is iOS 18.2 and later, and the `NSWindow` variant is macOS 15.2 and later.
- `PurchaseAction.callAsFunction(_:options:)` returns `Product.PurchaseResult` and is `@MainActor`.
- `Product.PurchaseResult` cases used here: `.success(VerificationResult<Transaction>)`, `.pending`, `.userCancelled`.
  Apple's example calls `transaction.finish()` for a verified success.
- `Product.PurchaseError.productUnavailable` exists and conforms to `Error`.
- `RequestReviewAction` is not available on tvOS or watchOS, and Apple's `requestReview(in:)` page says not to call it in
  response to a button tap. Both reasons support cutting `.appStoreReview`.
- macOS 15 and later: an app distributed outside the Mac App Store which uses a `group.…` App Group name can trigger a
  "would like to access data from other apps" alert. Apple's reply in
  <https://developer.apple.com/forums/thread/758358> says non-Catalyst Mac apps should use Team ID-prefixed group names,
  and that Mac App Store apps may use `group.…` names. I put a note about this in the README's Scope section.
- Dependencies exist at the tags `Package.swift` asks for (SpecialString 1.2.0, SerializationTools 1.1.1, SimpleLogging 0.5.2).
- `SpecialString` gives the identifier `ExpressibleByStringLiteral`, `Hashable`, `Codable`, and `Sendable`
  (when its special type is `Sendable`, which ours is). Its `rawValue` is deprecated in favor of `withoutTypeSafety()`.
- SerializationTools: `Encodable.jsonString()` and `Decodable.init(jsonString:)`. Reading the source, `init(jsonString:)`
  forwards every decoding strategy to `init(jsonData:)` except `keyDecodingStrategy`. Harmless as long as I use the
  default. Dates use `.iso8601`, which I believe has whole-second precision. That's fine for schedules measured in weeks.
- SimpleLogging: global functions like `log(warning:)` and `log(error:)`. Their default `channels` argument is
  `LogManager.defaultChannels`, a mutable `static var`. The package declares `swift-tools-version:5.2`.
  By default it prints `info` and above via `print`. I will log only warnings and errors, and only for real anomalies.


### Purchase sheet placement

`MonetizationPromptAction.perform(id:)` receives no window, scene, or environment, so an action can't reach a
`PurchaseAction` or `openURL`. Without that, the choices are:

- `Product.purchase(options:)`, which Apple doesn't list for visionOS, so it can't be the only path there.
- Finding a `UIScene` or `NSWindow` by hand through `UIApplication` or `NSApp`. That's fragile, and needs different code
  on each platform and OS version.

Cleaner: `MonetizationPrompt` is a SwiftUI view, so it can read `@Environment(\.self)` and hand the `EnvironmentValues`
to the action. Then `.storeKitPurchase` calls `environment.purchase(product)`, which is correct on every platform in
`Package.swift` and places the sheet in the right scene by construction. A custom action like the README's Ko-fi
example gets `environment.openURL` too, which is the SwiftUI way to open a link on all five platforms.

This changes the public protocol: `perform(id:)` becomes `perform(id:in:)`. It also makes a dev-facing "which window"
option unnecessary: a dev who wants a specific scene puts the prompt in that scene's view. **Asked Ky. Waiting.**


### Plan

Order of work. For every file: doc comments first, then the body.

1. `PromptHistory` (internal). Two states: `.tracking(interval:nextEligible:)` and `.done`. Custom `Codable` so `.done`
   encodes as exactly `{"done":true}`, as the README promises. Pure functions decide what happens when a prompt appears,
   given a stored record (or none), the current time, and the interval declared by the descriptor.
2. `PromptStore` (internal, `@MainActor`). Reads and writes one JSON string per prompt in `UserDefaults`, under the key
   `MonetizationTools.prompt.<identifier>`. That key format is a compatibility promise: changing it later would re-ask
   everyone who ever declined. The store takes a `UserDefaults` value, so tests can use an ephemeral suite.
   A read returns an enum (`neverChecked`, `recorded`, `unreadable`) rather than an optional, because the style guide
   forbids optional returns from throwing functions and because "unreadable" has to be told apart from "never checked".
3. `MonetizationPromptScope`: `.perApp` and `.appGroup(_:)`. The README calls `.appGroup("group…")` with an unlabeled
   argument. The style guide says to always label associated values. The README's call shape wins, so the case is
   `appGroup(_ identifier: String)`. This is a deliberate deviation from the guide; I've told Ky.
4. `MonetizationPromptStyle` protocol, its configuration, its environment entry, and `.monetizationPromptStyle(_:)`.
   The environment stores a type-erased style (`AnyView` inside), since an existential style can't return `some View`.
5. `MonetizationPromptFlow` (value type, `@MainActor`). Holds the descriptor, the store, the environment snapshot, and a
   binding which hides the prompt.
   - `present()`: runs the action. `.succeeded` records `.done` and hides. `.abandoned` records nothing. A throw
     propagates and records nothing. A second call while one is running returns immediately, so a double tap can't
     start two purchases.
   - `decline()`: records `.done`, hides.
   - `snooze()`: hides.
6. `MonetizationPrompt`: fix `body` and wire it up.
7. `StoreKitPurchaseAction`, `.storeKitPurchase`, `.storeKitPurchase(productId:)`. Steps: `Product.products(for:)`, throw
   `Product.PurchaseError.productUnavailable` if empty, `environment.purchase(product)`, then map the result.
   - Verified success: `await transaction.finish()`, return `.succeeded`.
   - Unverified success: throw the verification error, and don't finish the transaction. Nothing is recorded.
   - `.pending` (Ask to Buy) and `.userCancelled`: `.abandoned`.
   - An unknown future case: log a warning, `.abandoned`.
   - No `Transaction.updates` listener. The README promises no setup step, so an Ask to Buy purchase approved later
     isn't finished by this package. Documented in the action's doc comment.
8. Tests (Swift Testing), replacing the placeholder:
   - interval math (weekly, monthly, January 31st clamp, leap day)
   - the decision table (first contact, before eligible, exactly at eligible, after, done, cadence locked)
   - JSON: `.done` is exactly `{"done":true}`, round trips, garbage fails to decode
   - store behavior on an ephemeral `UserDefaults`, including unreadable data
   - flow behavior with fake actions (success, abandon, throw, double call, snooze, decline)
   - result mapping for `.pending` and `.userCancelled`. `.success` can't be built without StoreKitTest and an Xcode-made
     `.storekit` file, so verified purchases need a manual test in Ky's build.
9. Adversarial review pass, and a manual test list for Ky's build (see below).


### Behavior decisions I made without asking

Each follows from an invariant Ky already stated. Ky can overrule any of them.

- **Unreadable stored data fails closed**: the prompt doesn't show, and I log an error. Reason: never annoying someone
  beats never missing a chance to ask. Cost: a bug that corrupts a record silently retires that prompt.
- **A misconfigured App Group fails closed** the same way, with `assertionFailure` in debug builds. Falling back to
  per-app storage would break "a suite can't nag harder than any one app".
- **The first check never shows.** It records `.tracking` with `nextEligible` one interval away, which locks the cadence.
- **Showing a prompt advances its schedule** to one interval after the moment it appeared. Without that, ignoring a
  prompt would make it reappear on the next visit, breaking the weekly cap. This contradicts one README sentence
  ("Only `snooze()` and `decline()` change anything"), so I asked Ky. Waiting.
- **An already-visible prompt is left alone when its view appears again.** The decision is made only while hidden, so a
  prompt never vanishes under someone returning to a screen.
- **Ask to Buy (`.pending`) maps to `.abandoned`.** That makes the commented-out `pending` case unnecessary. I'd delete
  it. Asked Ky to confirm.
- **Only warnings and errors are logged.** Nothing at `info` or below, so shipping apps don't print anything routine.


### Unverified

I couldn't compile or run any of this. Where I guessed, I'll say so in the code review notes too.

1. `Descriptor(…, action: .storeKitPurchase)`: implicit member syntax when the parameter type is `any MonetizationPromptAction`.
   If it fails, make the initializer generic over the action.
2. A `static var storeKitPurchase` next to a `static func storeKitPurchase(productId:)`. I believe the labels make these
   distinct, but I haven't confirmed it.
3. `case appGroup(_ identifier: String)` with an unlabeled associated value.
4. SimpleLogging's default argument `LogManager.defaultChannels` (a mutable static from a Swift 5 mode package), used from
   Swift 6 mode code. The build may flag it.
5. `@Entry` for the style's environment value, with a non-`Sendable` stored value.
6. Passing `EnvironmentValues` (not `Sendable`) into an `async`, `@MainActor` function. I believe it's fine because both
   ends are on the main actor.
7. **Cold start, hidden prompt:** the skeleton runs its check in `.onAppear` on a `Group` which contains nothing while
   the prompt is hidden. I suspect `.onAppear` doesn't fire for an empty group, which would mean the very first check
   never happens and the cadence is never locked. I'll attach the check to something which always exists. The catch:
   that must not add a gap to the dev's `VStack`. This needs a real run to settle.
8. SimpleLogging, SerializationTools, and their transitive dependencies must all build on the five platforms in
   `Package.swift` (tvOS, watchOS, and visionOS included). I only checked their manifests.


### Manual test list for Ky's build (to be finalized with the code)

- Cold start: launch fresh. A hidden prompt still records its first check (see item 7 above).
- A hidden prompt leaves no gap inside a `VStack`.
- The prompt never appears while someone is on the screen; it waits for the next visit.
- Purchase sheet appears in the right window on iPad multi-window and on visionOS.
- Cancelling the sheet leaves the prompt on screen. A completed purchase hides it and never shows it again after a relaunch.
- `decline()` never shows it again after a relaunch.
- App Group scope: decline in app A, confirm app B never shows it. On macOS outside the Mac App Store, confirm no
  system alert appears with a Team ID-prefixed group name.
- Build on all five platforms.


### Not doing

- `.appStoreReview` (Ky cut it).
- An entitlement check for already-paid users (Ky declined; a payment or a decline is what retires a prompt).
- Dropping SerializationTools or SimpleLogging (Ky declined).
- A dev-facing parameter for which window shows the purchase sheet, if Ky approves the environment approach.
- A `Transaction.updates` listener (would need a setup step, which the README rules out).
- Touching `CONTRIBUTING.md` or the DSMP wording in the LLM transparency README.


### Doc changes so far

- `README.md`: removed `.appStoreReview` from the Actions section. Added a note about App Group names on macOS to the
  Scope section.
- `LLM transparency/README.md`: added a line for Claude 5 Sonnet under Claude.
- This journal.
