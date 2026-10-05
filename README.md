# Swift `MonetizationTools`

Monetize your SwiftUI app in consistent, user-friendly ways.

This package gives you the tools to create monetization flows in your app which never annoy the user; they're all opt-in and fail safely to modes which can't result in bad UX.

You're in charge of the UI, and this package handles the UX. That means you say what it looks like and this package says how it works.



## Scheduled monetization prompts

This uses a declarative system for presenting UI to the user asking them to pay or donate. These requests appear on a schedule you set, wherever you say they appear.

First, you describe the prompt's metadata (identifier, scheduling frequency, what happens when the user accepts, etc.):

```swift
import MonetizationTools

extension MonetizationPrompt.Descriptor {
    
    /// Notify the user that they must purchase a license to continue using the app
    static let licensePurchase = Self(
        "com.example.licensePurchaseNotice",
        atMost: .monthly,
        action: .storeKitPurchase
    )
}
```

Then you build the prompt into your own UI:

```swift
import SwiftUI
import MonetizationTools

struct MyView: View {
    var body: some View {
        VStack {
            normalContent

            MonetizationPrompt(for: .licensePurchase) { flow in
                Text("Purchase a license?")
                Button("Purchase now") { flow.present() } // If you want to react to payment errors, `try await` this
                Button("Later") { flow.snooze() }
                Button("Never") { flow.decline() }
            }
            .monetizationPromptStyle(.default)
        }
    }
}
```

Then your monetization prompt will appear automatically, where you placed it, without any further code. Only user actions can hide it again.

And that's it! There is no setup step, no `configure()` call, no app-launch registration. This package handles all that automatically.


### Scope

By default, a prompt's state is tied to the current app. If you prefer, then your prompt's state can be shared across your apps by using the `.appGroup` scope:

```swift
static let supporterUnlock = Self(
    "org.example.supporterUnlock",
    atMost: .monthly,
    scope: .appGroup(id: "group.org.example.apps"),
    action: .storeKitPurchase
)
```

Declining, snoozing, or completing it in one app then does the same in all of them, so an app suite feels cohesive.

> #### A note on non-App-Store Mac apps
> On macOS, an app distributed outside the Mac App Store should name its group with its Team ID as the prefix (like `ABCDE12345.org.example.apps`) instead of `group.…`. If you don't, then macOS 15 and newer will show an alert saying your app "would like to access data from other apps", which this package can neither detect nor prevent.
> 
> For more info, see [this forum thread](https://developer.apple.com/forums/thread/758358).


### Styling

You are in charge of how the prompt actually looks. The contents are entirely provided by you (there is no builtin default prompt content), and you may build your own styling from scratch or use a premade style.

This package includes `MonetizationPrompt.Style`, which operates like `ButtonStyle` does for a button.

Two styles ship with this package:

- `.default` • a reasonable default appearance, designed to fit in with platform apps
- `.plain` • no styling is applied whatsoever

You can write your own by conforming a new type to `MonetizationPrompt.Style`.


### Actions

`MonetizationPrompt.Action` describes exactly what kind of payment action is taking place (StoreKit, Patreon, PayPal, etc.).

This package currently ships one, but plans to include more in the future:

- `.storeKitPurchase` • Presents the system's builtin StoreKit purchase sheet. By default it uses the purchase desscription's ID as the product ID, but you can specify a different one by adding `productId:`:
    ```swift
    static let buyCoins = Self(
        "org.example.buyCoins", // Just for MonetizationTools
        atMost: .monthly,
        action: .storeKitPurchase(productId: "org.example.purchase.coins") // Sent to Apple
    )
    ```
    Use one prompt identifier for one product. If the product is a consumable, don't also offer it through your own StoreKit code; your code can finish the purchase before this package sees it.

Of course, you can build your own action by conforming a new type to `MonetizationPrompt.Action`. The scheduling, storage, and presentation machinery are still handled by this package, not by your new action. Your action is passed the SwiftUI environment of the prompt showing it, so it can use environment values like `openURL`, `purchase`.

Your implementation of the `perform(id:in:)` function can `await` anything for as long as it needs to, but must eventually return an `Outcome` (`.succeeded`, `.pending`, or `.abandoned`). If it returns `.pending`, then your action also has to implement `checkPending(id:)`, which reports the result later.

`checkPending` is yours to get right. After `perform` returns `.pending`, it's the only way this package learns what happened. Return `.succeeded` when you know the person completed it. Return `.abandoned` only when you know for certain that it won't complete. In every other case, including a failed request or an unreachable server, return `.currentStateUnknown`. Returning `.abandoned` by mistake brings the prompt back for someone whose first attempt may still be open.

Put a button that calls `flow.decline()` in your prompt's content. Someone who already paid and sees the prompt again can use it to end the prompt.

```swift
struct KoFiLinkAction: MonetizationPrompt.Action {
    let donationPageUrl: URL

    @MainActor
    func perform(id identifier: MonetizationPrompt.Identifier,
                 in environment: EnvironmentValues) async throws -> Outcome {
        environment.openURL(donationPageUrl)
        return .pending
    }

    func checkPending(id identifier: MonetizationPrompt.Identifier) async -> Outcome {
        // Ask your own server whether Ko-fi's webhook reported a payment for this prompt.
        // If it didn't, or if your server couldn't be reached, you don't know yet.
        if await yourServerSaysTheUserDonated() {
            return .succeeded
        }
        else {
            return .currentStateUnknown
        }
    }
}
```


### While developing

Two tools make a prompt easy to work on without waiting weeks for it to come due. Both exist only in debug builds, so
every use of them has to be wrapped in `#if DEBUG` too, and none of it can reach a release build.

```swift
@State private var isShowingPrompt = false

var body: some View {
    #if DEBUG
    Toggle("Show prompt", isOn: $isShowingPrompt)
    #endif

    MonetizationPrompt(for: .licensePurchase) { flow in
        // …your usual content…

        #if DEBUG
        Button("Reset") { flow.reset() }
        #endif
    }
    #if DEBUG
    .debug(monetizationPrompt: .isShowing, $isShowingPrompt)
    #endif
}
```

- `.debug(monetizationPrompt: .isShowing, _:)` binds a prompt's visibility to your own `Bool`, both ways. Set it to show
  or hide the prompt right now, without changing its stored history. It also follows the prompt: when the prompt shows
  or hides for a real reason (its schedule, `snooze()`, `decline()`, or a purchase), your `Bool` changes to match.
  Each time the prompt's view appears, your `Bool` is reset to what the real schedule says.
- `flow.reset()` erases the prompt's stored history, so its next check behaves like the first launch after a fresh
  install. It doesn't hide the prompt by itself.


### Nitty-gritty

In case you really wanna know how this shit will actually work:

- **The prompt skips the first-run appearance** • If you use `atMost: .monthly`, then the first time the prompt appears will be one month after the first time the user loads that view. Every appearance after that is at least a month apart. This is to help prevent the user thinking of your app as nagware

- **Intervals are based on calendar dates** • This package uses Swift's `Calendar` API to calculate dates. For example, if the first check of a `.monthly` prompt is on February 20th, then it's be first shown on March 20th. If its first check is January 31st, then it's first shown 28th. Et cetera.

- **You cannot change the cadence after first-load** • Whatever `atMost:` is set to at the first time a prompt was ever checked, is what it will be from then on. This also applies to prompts which have passed their first-load check but haven't yet appeared. Changing it in a later version of your app won't affect existing users, again to prevent the user from being annoyed at the prompt.

- **No escalation mechanism** • There is no mechanism for making a prompt show more frequently as time goes on.

- **It never appears under the user's finger** • The prompt can only appear when its parent view appears, and will only disappear when the user dismisses/finishes it or the parent view disappearss. If the time comes for a prompt to be displayed while someone is currently on its screen, then the prompt will wait for the next time the user visits that screen rather than risking shifting the content while the user is actively using the app.

- **Only the user can proceed/dismiss** • If the user ignores it, it stays where it is. Only `snooze()`, `decline()`, or a successful purchase (`.present()`) changes when (or whether) it shows next. There's no way for you to programmatically show/hide a monetization prompt.

- **Errors and backing out don't affect the prompt** • If the user cancels a purchase sheet, or if some error occurs with purchasing, or the app crashes, etc., then the prompt stays where it is. Only explicit user action can dismiss/reschedule a monetization prompt

- **If a purchase needs someone else's approval, the prompt waits** • A purchase that needs approval, like Ask to Buy, replaces the prompt's content with a short message saying so. On later appearances the prompt is hidden, and the package keeps asking the action for the result. A success retires the prompt for good. If the result is that it didn't happen, or the package stops waiting, the prompt comes back later.

- **One product, one identifier** • Use one prompt identifier for one product. Two identifiers for one product is a mistake, and this package doesn't detect or work around it. You can use one identifier in more than one place, such as on two screens; they share one stored state. If more than one of them is on screen at once and the user acts on one, what the others show isn't defined until they next appear.

- **Minimal storage space** • A declined or fulfilled prompt is persisted with as little data as possible, so this package never takes up notable storage.



## Batteries included!

### It Just Works™

You never have to run setup code, nor ask this package to do something that needs to be done. You tell the package how to handle the payments and what your UI looks like, and it handles the rest.

`MonetizationTools` attempts to handle edge cases gracefully so you don't have to, and provides APIs to tweak that behavior as-needed.


### Payment handlers

This package ships with StoreKit already supported. Just use `.storeKitPurchase` when you make a prompt descriptor, and that prompt's payments will go through StoreKit.

You may also create your own payment handlers by conforming to `PaymentHandler`, for example if you want the user to pay you via Stripe, Ko-Fi, PayPal, etc..



## LLM transparency

[I, Ky,](https://KyLeggiero.me) reviewed all the code in this repo, and wrote the majority of it. Nothing gets into production code without my careful review and explicit approval, no matter who or what wrote it. See [the PRs](https://github.com/RougeWare/Swift-MonetizationTools/pulls) for proof of that.

A lot of it was written using LLMs, either directly writing it, or assisting contributors like myself.

Because transparency fucking matters, I'm making sure all of that is documented in the [LLM transparency](./LLM%20transparency) folder of this repo.
