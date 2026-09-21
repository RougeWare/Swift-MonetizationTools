# MonetizationTools

Voluntary funding mechanics for apps which never gate anything behind them.

Every ask this package can make is opt-in, dismissable forever in one tap, capped at weekly at its most frequent, and
incapable of escalating. Nothing here can withhold a feature, because nothing here knows how.

Version 0.0.1 ships one feature: the delayed prompt, plus a StoreKit-backed purchase action to pair with it.


## The delayed prompt

Declare a prompt once:

```swift
import MonetizationTools

extension MonetizationPrompt.Descriptor {
    static let licensePurchase = Self(
        "com.example.licensePurchaseNotice",
        atMost: .monthly,
        action: .storeKitPurchase
    )
}
```

Then put it wherever it belongs:

```swift
import SwiftUI
import MonetizationTools

struct MyView: View {
    var body: some View {
        VStack {
            normalContent

            MonetizationPrompt(for: .licensePurchase) { flow in
                Text("Purchase a license?")
                Button("Purchase now") { Task { try await flow.present() } }
                Button("Later") { flow.snooze() }
                Button("Never") { flow.decline() }
            }
            .monetizationPromptStyle(.default)
        }
    }
}
```

There is no setup step, no `configure()` call, no app-launch registration. The first time anything here needs a store,
it makes one.


## What the rules actually are

**It waits before the first ask.** `atMost: .monthly` means the first appearance is one month after the prompt is first
checked, and every appearance after that is at least a month apart. One value governs both, so a prompt can't nag sooner
than it waited the first time.

**Intervals are calendar-correct.** First checked on February 20th, first shown on March 20th. January 31st clamps to
the end of February the way `Calendar` normally clamps.

**The cadence is locked on first contact.** Whatever `atMost:` said the first time a prompt was ever checked is what
governs from then on — for anyone who has ever been checked for it, including someone still waiting on their first
appearance. Changing it in a later version of your app only reaches people who have never once been checked for that
prompt before, so nobody's cadence can be quietly ratcheted up by an update.

**It can't escalate.** `PromptInterval` is a closed set whose shortest case is `.weekly`. There's no way to spell
anything more frequent, and no way to make an interval shrink over time.

**It never appears under a finger.** Visibility is decided when the view appears and then left alone. A prompt whose
moment arrives while someone is sitting on the screen it lives on waits for the next visit rather than materializing
mid-tap and moving whatever they were reaching for.

**Only a person moves it along.** A prompt nobody answers stays where it is, and shows again each time its screen
appears. Only `snooze()`, `decline()`, or a completed purchase changes when (or whether) it shows next.

**Backing out isn't the same as refusing.** Cancelling a purchase sheet records nothing: the prompt keeps its schedule
and stays on screen. Only `snooze()` and `decline()` change anything, because only those are things a person actually
asked for.

**Retiring a prompt costs nearly nothing to remember.** A declined or fulfilled prompt persists as `{"done":true}` and
not one byte more. Someone who wanted none of this can't have their storage grow because of it.


## Scope

By default a prompt's history is this app's alone. Share it across a family of apps with an App Group:

```swift
static let supporterUnlock = Self(
    "org.example.supporterUnlock",
    atMost: .monthly,
    scope: .appGroup(id: "group.org.example.apps"),
    action: .storeKitPurchase
)
```

Declining it in one app then declines it in all of them, so a suite can't collectively nag harder than any one of its
members would.

On macOS, an app distributed outside the Mac App Store should name its group with its Team ID as the prefix (like
`ABCDE12345.org.example.apps`) instead of `group.…`. Otherwise macOS 15 and later can show the person an alert saying the
app "would like to access data from other apps", which this package can neither detect nor prevent. Apple describes the
rules [in this forum thread](https://developer.apple.com/forums/thread/758358).


## Styling

The contents are always yours. A `MonetizationPromptStyle` decides everything around them, the way `ButtonStyle` does
for a button.

- `.default` — a rounded rectangle with a secondary background
- `.plain` — nothing at all

Write your own by conforming to `MonetizationPromptStyle` and implementing `makeBody(configuration:)`.


## Actions

What happens when someone says yes is a `MonetizationPromptAction`. One ships with the package:

- `.storeKitPurchase` — presents the system purchase sheet. With no `productId:`, it uses the prompt's own identifier as
  the product ID, so a matching pair doesn't have to be typed twice.

Write your own by conforming to `MonetizationPromptAction`. Nothing about the scheduling, storage, or presentation
machinery needs to know what yours does. An action is handed the environment of the prompt showing it, so it can read
`openURL`, `purchase`, and the like without any setup of yours.

```swift
struct KoFiLinkAction: MonetizationPromptAction {
    let url: URL

    @MainActor
    func perform(id identifier: MonetizationPromptIdentifier,
                 in environment: EnvironmentValues) async throws -> MonetizationPromptActionOutcome {
        // Open the URL, then decide what that meant
        environment.openURL(url)
        return .succeeded
    }
}
```


## Requirements

iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+. Swift 6.

Depends on [SpecialString](https://github.com/RougeWare/Swift-Special-String) for the identifier type,
[SerializationTools](https://github.com/RougeWare/Swift-SerializationTools) for JSON persistence, and
[SimpleLogging](https://github.com/RougeWare/Swift-Simple-Logging) for diagnostic logging.



## LLM transparency

[I, Ky,](https://KyLeggiero.me) reviewed all the code in this repo.

A lot of it was written using LLMs, either directly writing it, or assisting contributors like myself.

Because transparency fucking matters, I'm making sure all of that is documented in the [LLM transparency](./LLM%20transparency) folder of this repo.
