# Issue #1 — MonetizationTools 0.0.1: the delayed monetization prompt

**Model:** Claude Opus 5
**Initial Director:** Ky
**Branch base:** `production` (work done on `feature/MVP`)

> **This journal was backfilled, not written as I went.** `AGENTS.md` is explicit that writing it afterward is the
> failure mode, and that's what happened here: the repo's markdown files were added after my work was already done, so I
> didn't know the requirement existed while I was working. Ky asked me to reconstruct it from our conversation.
>
> That means the dated sections below are a reconstruction, and the usual warning applies — a story written at the end
> is biased toward the path that worked. I've deliberately kept every dead end I can actually remember taking, and where
> my memory of the ordering is fuzzy I've said so rather than inventing a clean sequence. The technical claims are
> checkable against the diff; the narrative ordering is the part to trust least.

The work: build the first feature of `MonetizationTools`, a RougeWare Swift package for voluntary funding mechanics
across the Deadass Simple app family. Feature one is the delayed prompt — a WinRAR-style "would you like to support
this?" ask that is never a gate, never escalates, and never appears under someone's finger.

I was not given a free hand on API design. Ky directed the API surface throughout and I proposed against it; where those
two disagreed, Ky's call won. The rejected alternatives below are mostly mine, and are recorded because they're the part
a future maintainer can't reconstruct from the code.


## 2026-09-14 — API design, before any code

**Model:** Claude Opus 5
**Director:** Ky

Ky opened with a target call site: a `@MonetizationPrompt("some.id", atMost: .monthly)` property wrapper exposing
`shouldShow`, `snooze()`, and `cancelForever()`, explicitly *not* as complex as TipKit, with the developer keeping full
control of the visuals via a plain `if` statement.

Things I raised, and where each landed:

**A free `shouldShow(monetizationPromptWithId:)` function can't work.** SwiftUI has no way to know a bare function call
in `body` depends on anything, so nothing re-renders when the prompt's state changes. This is why the design moved to
something that participates in view identity. Not a dead end so much as the constraint that ruled out Ky's very first
sketch.

**I claimed `shouldShow` couldn't record "we displayed it" because `body` may be evaluated more times than the screen
renders. Ky pushed back, and Ky was right.** The precise hazard is a *getter* performing a side effect that needs
exactly-once semantics. Nothing in this design needs that: the only body-time write is "create a record if none exists,"
which is idempotent, and every other state change comes from an explicit button press. I was still arguing against an
earlier, vaguer version of the problem. Worth recording because the idempotence is now load-bearing and unguarded — see
`MonetizationPromptStore.shouldShow(_:now:)`, which relies on it structurally rather than defending it with a flag.

**Counting the interval from last *dismissal* rather than last *display*.** Falls out of the above. `snooze()` happens
at a known moment; "was displayed" doesn't. Consequence, accepted deliberately: an ignored prompt stays on screen until
dismissed rather than timing itself out. Ky considers that correct — it's inline content, not a modal, and "if I didn't
change it, it didn't change" is a stated win condition for Deadass Simple apps.

**Ky then reframed the whole thing**, mid-message, from a property wrapper to a container view with a trailing closure
plus a `ButtonStyle`-shaped style modifier. That's what shipped. The motivation was that a container view gets
`.onAppear`, which is a real lifecycle event, so visibility can be decided when the view appears and then left alone —
guaranteeing the prompt never materializes mid-session under a finger that was already moving.

### Rejected: non-escalation as a type-level guarantee

I proposed making escalation *unrepresentable* rather than merely documented:

```swift
public enum BackoffFactor: Sendable, Hashable {
    case staysTheSame
    case doubles
    case triples
}
```

No case spells "halves," so no conforming policy can tighten over time. Ky rejected it as over-engineered and replaced
it with something simpler that achieves more: a single closed `PromptInterval` whose shortest case is `.weekly`, with
the chosen interval **persisted on first check and read from storage forever after**, so a later app update can't
quietly ratchet up an existing user's cadence either. Same instinct, better scoped. Don't re-propose the backoff enum.

### Dead end: stable hashing of an arbitrary `Hashable` identifier

Ky wanted the identifier to be any `Hashable` (their own `enum`, a `Namespace.ID`, whatever), with the storage key being
a runtime-stable hash of it, and asked whether supplying a custom `Hasher` would get that.

It can't. `Hasher` is a concrete struct, not an algorithm slot, and its seed is **randomized per process launch on
purpose** as a hash-flooding defense; the standard library documents that hash values aren't guaranteed to match across
executions of the same program. No `Hasher` configuration yields something safe to write to disk. This is a genuine wall
— don't spend time here again.

Two intermediate proposals, both superseded:

1. A `MonetizationPromptIdentifiable: Hashable` marker protocol with a `promptStorageKey: String` requirement.
2. The same, conforming to `EssentiallyAString` from RougeWare's `SpecialString`, which already guarantees a stable
   `description` equal to `rawValue`, making the extra requirement unnecessary.

I noted that (2) has a gap: `EssentiallyAString` requires `RawRepresentable where RawValue == String`, and plain `String`
doesn't conform to `RawRepresentable`, so a bare string literal identifier wouldn't have worked without adding a
conformance. Ky called that an oversight in their own package and chose instead to make the identifier a **concrete**
`SpecialString` special type. That's what shipped (`MonetizationPromptIdentifier`), and it makes the whole hashing
question moot: there's exactly one identifier type, it's always a stable string, and hashing it is trivial.

Also considered and dropped: deriving the key by hashing an `Encodable` round-trip of the identifier. Ky's own
reservation about predictability was correct, and once the identifier was concrete it solved nothing.

**Storage key detail worth knowing:** the key is SHA-256 of the identifier string, hex-encoded, **truncated to 8 bytes /
16 hex characters**. Full SHA-256 hex is 64 characters, which is longer than most reverse-DNS identifiers and defeats
the point. Truncation is safe at the scale involved (single-digit prompt counts per app), but it is a truncation, and if
that ever stops being true this is the line to revisit: `MonetizationPromptStore.key(for:)`.

### Rejected: an `enum` for what the prompt does when someone says yes

Ky initially floated an `enum`, then argued themselves into a protocol in the same message. Agreed, and for a hard
reason rather than taste: an `enum` is closed, so a third party can never add a case, which directly contradicts the
stated goal of developers writing their own. `MonetizationPromptAction` is a protocol for that reason alone.

I also proposed that `present()` take a caller-supplied async action, keeping the package honestly decoupled from
payments. **Ky rejected this**: the point of `MonetizationTools` is to be a sugary wrapper that owns the StoreKit /
Stripe / Ko-fi / GitHub Sponsors mess so app code doesn't have to. The protocol is the extension point; the built-in
conformances are the package's actual job.

### Deliberately not built

- **Clock-tamper defense.** Wall-clock time can move backwards and the usual fix is a stored high-water mark. Ky
  declined it outright: nothing here is gated, so the worst a tamperer achieves is not being asked for money, which is
  their right. No monotonicity check exists. This is a choice, not an oversight.
- **`flow.isPending` or any reactive surface for StoreKit's Ask-to-Buy state.** I raised it and got no answer, so I
  didn't invent it. A `.pending` purchase currently leaves the prompt sitting there unchanged; showing "waiting for
  approval" is the app's job, off `present()`'s return value.
- **Cross-screen propagation of retirement.** A purchase completed in one place does not close a prompt already on
  screen elsewhere; the snapshot-on-appear model has no notion of publishing change. I flagged this as the seam where a
  future observable store would go. Ky confirmed on 2026-09-15 that this is acceptable and consistent with the "if I
  didn't change it, it didn't change" philosophy, so it is now an accepted property rather than an open item.


## 2026-09-14 — Initial implementation

**Model:** Claude Opus 5
**Director:** Ky

Wrote the package: identifier, `PromptInterval`, scope, record, store, action protocol + two conformances, descriptor,
flow, view, style protocol + two styles, plus a small test suite. Layout is standard SwiftPM.

Two decisions I made without being asked, both flagged to Ky at delivery:

**`StoreKitPurchaseAction` is a real implementation, not a stub.** Ky had said "no StoreKit stuff yet" during the design
phase. I judged that `.storeKitPurchase` existing as a hollow shell was worse than ~40 lines that work, and implemented
it. Ky did not object. If this was the wrong call it's cheap to gut.

**`AppStoreReviewAction` was not requested at all.** I added it as a second conformance specifically to demonstrate that
the action protocol isn't payment-shaped — it proves the scheduling machinery genuinely doesn't care what an action
does. It is arguably scope creep. Ky did not object.

**`MonetizationPrompt` is non-generic and erases its content to `AnyView` internally.** This is forced, not stylistic.
If the view were generic over `Content`, the nested `Descriptor` would be implicitly generic too, and
`extension MonetizationPrompt.Descriptor { static let licensePurchase = ... }` — the declaration syntax Ky specified —
would not work, because the static would be attached to one specific content type. Non-generic buys the call site Ky
asked for at the cost of one `AnyView` per prompt, on a small and near-static subtree. If someone later "optimizes" this
by making the view generic, the descriptor extension syntax breaks. That's the tradeoff.

`action:` has no default and is therefore a required parameter. A prompt that can't do anything when someone says yes is
meaningless and I couldn't justify a default. Side effect: the `Self("...", atMost: .monthly)` shorthand used in earlier
design sketches does not compile.


## 2026-09-15 — Review pass against the `principal-software-architect-style` skill

**Model:** Claude Opus 5
**Director:** Ky

Ky had intended the implementation to run under a particular review style and asked me to apply it retroactively. It
caught one real defect, which had nothing to do with writing style:

**`MonetizationPromptStyleConfiguration.Content` would not have compiled.** It was a `public struct` conforming to the
public `View` protocol with `internal let body: AnyView` — a protocol witness less visible than its conformance, which
Swift forbids. SwiftUI gets away with the same shape in `ButtonStyleConfiguration.Label` only because that's a primitive
view with `Body == Never` that the framework renders natively; we have no such privilege. Fixed by holding the erased
content in an internal `wrapped` and exposing a public `body` that returns it.

**Also removed `Sendable` from the `MonetizationPromptStyle` protocol**, arguing the constraint bought no safety because
a style is only ever evaluated on the main actor during body construction. That reasoning was correct about the *usage*
sites and wrong about the *construction* site, which caused a compiler error the next day. See below.

Remaining changes in this pass were documentation hygiene: identical concepts (`notCompleted` semantics, stated in both
`MonetizationPromptActionOutcome` and `present()`) reworded to match exactly, and two doc comments removed that were
addressing Ky rather than a future API consumer.


## 2026-09-15 — Two compiler errors from Ky's build

**Model:** Claude Opus 5
**Director:** Ky

I have **no Swift toolchain** in my environment, so nothing I wrote was ever compiled by me. Ky built it and returned
two errors. Both are cases where I asserted something about an external API without checking it.

### 1. `sending 'style' risks causing data races` in `AnyMonetizationPromptStyle.init`

Symptom: `self._makeBody = { AnyView(style.makeBody(configuration: $0)) }` where `_makeBody` was typed
`@MainActor (Configuration) -> AnyView`.

Cause: dropping `Sendable` from the style protocol the previous day was defensible for usage but ignored where the type
gets *constructed*. `AnyMonetizationPromptStyle.init` is also the expression evaluated for `@Entry`'s synthesized
default value, which runs in a nonisolated context. Forming a closure whose type promises main-actor isolation, while
capturing a non-Sendable value, from code not itself on the main actor, is precisely what the diagnostic names.

Fix chosen: **not** restoring `Sendable` (the usage-site reasoning still holds and the constraint would burden every
conformer). Instead, erase through a generic box — a private `MonetizationPromptStyleBox` protocol with a
`ConcreteMonetizationPromptStyleBox<Style>` conformer — so the one isolated operation is deferred to a method call that
only ever happens from `makeBody(configuration:)`, already correctly annotated. `init` becomes unremarkable, which is
what `@Entry` requires of it.

I believe this is the right fix rather than a suppression, because it removes the isolation promise from the point where
it couldn't be honestly made instead of asserting the promise harder. I could not verify it by compiling.

### 2. `missing argument for parameter 'in'` — `AppStore.requestReview()` on macOS

This one is straightforwardly my error. I wrote a scene lookup for iOS correctly, then assumed macOS had a simpler
scene-less overload and called `AppStore.requestReview()` from memory. It does not exist. macOS has exactly one
overload, `requestReview(in: NSViewController)`, mirroring iOS's `requestReview(in: UIWindowScene)`. I had it backwards:
macOS is the more awkward platform here, not the easier one.

Fixed by mirroring the iOS branch — walk `NSApplication.shared` for the key (or main) window and use its
`contentViewController`, returning `.notCompleted` if there isn't one.

**Known limitation, Apple's not ours:** a windowless or menu-bar-only macOS app has no `NSViewController` to hand
StoreKit, so `.appStoreReview` silently returns `.notCompleted` there. There's an open Apple feedback report and
developer forum thread about exactly this. Nothing to fix on our side.

After these two, I swept the package by hand for the same failure class (actor-typed closures formed from code not
provably already on that actor) and found two more `@MainActor` closures in `MonetizationPromptFlow`, both constructed
from inside `MonetizationPrompt`, which is implicitly main-actor-isolated via its `View` conformance. I believe those
are fine under the same reasoning that fixed error 1, but that is reasoning and not a build.

Ky confirmed on 2026-09-15 that these resolved all compiler errors.


## Verification status

**Nothing in this package was compiled or run by me at any point.** No Swift toolchain was available in my environment
for any part of this work. Ky compiled it; that is the only evidence it builds.

The tests in `Tests/MonetizationToolsTests/` were written but **never executed by me** — they cover `PromptInterval`
calendar math (including the January 31st → end-of-February clamp) and `MonetizationPromptRecord` encoding (including
asserting the exact `{"done":true}` shape). They should be run before this merges.

Specifically untested by anyone as far as I know, and worth real attention in review:

- The App Group path. `MonetizationPromptScope.appGroup(_:)` falls back to `UserDefaults.standard` when
  `UserDefaults(suiteName:)` returns nil, which happens when the app lacks the entitlement. That fallback is silent, and
  means a misconfigured App Group degrades to per-app behavior rather than failing loudly. I'm not certain that's the
  right call and didn't raise it with Ky at the time.
- An app using both `.perApp` and an App Group gets two independent stores persisting under the same defaults key in
  different suites. I believe that's correct; it's never been exercised.
- Every StoreKit path, including the `.pending` / Ask-to-Buy branch.
- `@Entry` requires recent tooling; if the deployment toolchain objects, it's a mechanical swap back to a manual
  `EnvironmentKey`.
- `.background(.background.secondary, in: .rect(cornerRadius: 12))` in `DefaultMonetizationPromptStyle` is the single
  line I'd most expect to need adjusting across platforms.
