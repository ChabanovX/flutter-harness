# Stateful Orchestrator Readability

## Goal

Stateful controllers, adapters, coordinators, services, Cubits, and Blocs must
make ownership and ordering understandable from the code itself. A large class
is not automatically wrong, but a maintainer must be able to change one
lifecycle phase without first reverse-engineering the entire file or relying on
Git history and author explanations.

## Semantic review triggers

Run the readability reviewer when a changed production Dart class owns mutable
state or lifecycle work and any of these signals applies to the full class:

- 350 or more lines;
- 18 or more methods;
- 12 or more instance fields;
- 3 or more owned async/lifecycle mechanisms, such as in-flight task slots,
  timers, stream controllers or subscriptions, cancellable handles, or
  generation/revision tokens.

Also run it below those thresholds when a change introduces or expands coupled
startup, retry, invalidation, or shutdown orchestration. Generated files are
excluded.

These numbers select a semantic review; they are not quality failures and must
never be used to demand a mechanical split. A cohesive 500-line adapter can be
clearer and safer than five helpers with hidden shared ownership.

## Cold-read contract

Before reading change descriptions or another reviewer's conclusions, a
reviewer should reconstruct these facts from the class, its direct contracts,
and its nearest tests:

1. Its single responsibility and what remains outside it.
2. Its lifecycle phases and the order in which they can run.
3. The readiness gates that permit work to start.
4. Every owned task, timer, controller, subscription, or resource and who
   completes, cancels, or disposes it.
5. How stale asynchronous completions are invalidated.
6. Failure, retry, and close ordering, including partial-startup cleanup.
7. Which concerns are genuinely cohesive and which could be extracted behind a
   smaller ownership boundary.

The reviewer validates that reconstruction against callers and tests after the
cold pass. If the source suggests two plausible but incompatible models, the
ambiguity is evidence; the reviewer still needs a credible maintenance failure
before publishing a finding.

## Writing for local reasoning

- Give entry points domain verbs and make guards visible in names, such as
  `openFrameSourceIfNeeded` or `invalidatePendingReplay`.
- Use the class Dartdoc to state responsibility boundaries and lifecycle
  guarantees, not to narrate every member.
- Keep lifecycle entry points short enough to read as an ordered story; move
  phase-specific mechanics behind names that state their postcondition.
- Name task slots and completion handlers after the work they own. Clear a slot
  only when the completing task is still the active one.
- Group related state and methods when that makes ownership visible. Section
  dividers are acceptable in a long file under the commenting conventions.
- Comment private code only for hidden invariants, race reasoning, platform
  constraints, or non-obvious fallback policy. Rename a vague method before
  adding a comment that merely translates it.
- Extract a collaborator when it can own a cohesive lifecycle and expose a
  narrow contract. Do not extract helpers that continue mutating the parent's
  private state through callbacks or shared bags of fields.
- Preserve ordering and race behavior in focused tests; prose is not a
  substitute for executable coverage.

## Before and after

This call sequence hides both its guard and the ownership represented by the
completion callback:

```dart
await _startFrameSourceOpen();

_inferenceFuture = replayFuture;
replayFuture.whenComplete(
  () => _releaseInferenceFuture(replayFuture),
);
```

Prefer names that let the lifecycle read as a sequence of postconditions:

```dart
await _openFrameSourceIfNeeded();

_activeReplayTask = replayTask;
replayTask.whenComplete(
  () => _clearActiveReplayTaskOnCompletion(replayTask),
);
```

The second version does not make the containing class automatically readable.
It removes two local ambiguities; the reviewer still reconstructs the complete
responsibility, readiness, invalidation, retry, and shutdown model.

## Review outcome

A readability finding must cite named symbols, state the model that a cold
reader cannot determine safely, and connect that ambiguity to a credible future
race, leak, invalid transition, or broken cleanup order. Line count, subjective
style, and a generic request to "split the class" are not findings.

When suggesting extraction, identify the state and resources that move together,
the narrow contract they expose, and the ownership that remains in the parent.
If no such boundary improves local reasoning, record why the class should stay
together and return no finding.
