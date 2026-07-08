# Comments and Code Documentation

These rules formalize the project's accepted commenting style for Dartdoc
(`///`), inline comments (`//`), TODOs, lint suppression, section dividers, and
localization metadata. They are based on the actual codebase style used in
`lib/`, `packages/dpad_v2/`, and `test/`, and they are required for new code.

None of these rules is enforced by linting. The analyzer preset keeps
documentation lints disabled, so compliance is checked during code review.

## 1. General Principles

- Prefer self-documenting code: semantic names are more valuable than comments.
- A comment explains why, not what: constraints, platform traps, non-standard
  decisions, or behavior that is not visible from the code itself.
- A comment that paraphrases the next line is noise. Do not write it.
- Comments are not review notes ("fixed here") or changelog entries ("used to
  work differently"). History belongs in Git.

```dart
// Bad: repeats the code.
// When: load('7')
await cubit.load('7');

// Good: records a hidden constraint.
// Evict non-displayed decoded images only. Do NOT call clearLiveImages() - it
// removes images currently on screen, causing visible white rectangles.
```

## 2. Comment Language

- Production code under `lib/` and `packages/` uses English for both Dartdoc and
  inline comments.
- Russian is allowed only when quoting UI text or Jira ticket wording:

```dart
// "Кто будет тренироваться?" picker.
// TV-764: feature "Дни в ритме" is reliable from 2026-05-25 onward.
```

- Tests are the only code location where Russian prose is tolerated in
  Given/When/Then-style annotations.
- Project Markdown documentation, such as this file, `AGENTS.md`, and rule
  documents, may use Russian when the repository chooses that style.

## 3. Dartdoc (`///`)

Document these:

- every public class, typedef, enum value, and field in the public `dpad_v2`
  package API;
- use cases under `lib/domain/use_cases/`;
- Cubits and blocs, including their purpose and responsibility boundaries;
- domain models under `lib/domain/models/`, including the class and non-obvious
  fields;
- public reusable widgets under `lib/ui/widgets/`, with class-level docs;
- every design-system token constant.

Do not document obvious fields such as `id` or `title`. The data layer, including
mappers, DTOs, and repository implementations, is documented only when needed.

Use one summary sentence, then an empty `///` line, then details. Use
`[Identifier]` for cross-references. Do not put code examples in Dartdoc;
examples belong in Markdown docs such as `AGENTS.md` and `DPAD.md`.

```dart
/// Applies a streak freeze for the current day.
///
/// Returns the backend status string. Callers should refetch the freeze info
/// and statistics afterwards, since the endpoint returns neither.
```

For Cubits, document responsibilities as a list:

```dart
/// Manages current focus and screen lifecycle.
///
/// Orchestrates [RegionCubit] and [FocusMemoryCubit] to:
/// - Mount/unmount screen rules on transitions.
/// - Save/restore focus per screen.
/// - Cascade fallback when restoring (saved -> default -> any region -> sidebar).
```

For widgets with non-standard architectural choices, add a `Design decisions:`
block:

```dart
/// Generic horizontal TV slider.
///
/// Design decisions:
/// - Selection logic (multi-choice, "All" toggle) lives in the parent screen,
///   not in AppSlider.
```

Widget parameters are documented on fields, not constructors, following Dart
conventions. Size and color tokens cite their design source with a suffix:

```dart
/// Fixed width of TrainingCard (webos: w-[432px]).
```

## 4. Inline Comments (`//`)

Use inline comments for rationale, caveats, and platform traps. Common reasons:

- webOS, web renderer, or TV memory behavior;
- focus and D-pad timing;
- regression protection after an expensive bug investigation.

```dart
// On web (webOS HTML renderer) decoded bitmaps live in browser memory the byte
// cap can't measure, so also bound the ENTRY COUNT to force LRU eviction and
// stay under webOS's ~250-350MB auto-reload limit (TV-792).
```

```dart
// Flutter web's _defaultWebShortcuts deliberately omits arrow keys to avoid
// conflicting with browser scroll. TV navigation needs them back.
```

```dart
// Intentionally a plain GoRoute, NOT a ShellRoute. The previous ShellRoute
// builder discarded its `child`, crashing the exit-dialog flow (TV-123).
```

If a comment records the outcome of an expensive investigation, such as a crash,
memory limit, or platform workaround, include the `TV-xxx` ticket in the comment.

## 5. TODO

Use only `TODO`; do not use `FIXME`, `HACK`, or `XXX`.

Accepted formats:

- `// TODO: <action>` for simple cases;
- `// TODO(<category>): <action>` when a scope is useful.

The category is not an author. Use the blocker or scope, such as `backend`,
`workaround`, or `TV-xxx`. Do not put names in TODOs; ownership is recovered via
Git blame. A TODO must be actionable: it should say what to do and under which
condition.

```dart
// TODO(backend): switch to server-provided is_new_user if the auth API adds it.
/// TODO(workaround): Remove once backend provides CDN/HLS streams for kids.
```

Do not write TODOs that depend on fragile line numbers, such as
`// TODO: look at line 60.`

## 6. Lint Suppression (`// ignore:`)

Suppress lints rarely and as locally as possible. Prefer `// ignore:` on the
specific line. Use `// ignore_for_file:` only in generated files such as l10n
outputs and `*.g.dart`.

If the reason is not obvious from the suppressed line, add a short explanation
near the ignore.

## 7. Commented-Out Code

Delete commented-out code by default. Git preserves history.

Keep parked code only when it waits on an external condition, and only under an
explaining TODO:

```dart
// TODO(TV-000): favorite icon - uncomment when isFavorite is wired.
// if (isFavorite)
//   Positioned(...)
```

Commented-out code without an explaining TODO is a review issue.

## 8. Section Dividers

Long files, such as DI registration, token, constant, and analytics files, are
chunked with the accepted box-drawing divider format:

```dart
// ── Scaffold & canvas ───────────────────────────────────────────────
// ── CarrotQuest (separate from main analytics pipeline) ──
```

Do not use `#region`, `// MARK:`, or ASCII `// ----` separators. The divider is
also acceptable for small inline labels inside a large `build()` method:

```dart
// ── "N lessons by M min" ──
```

## 9. Localization (`.arb`)

Every key in `lib/l10n/app_ru.arb` has matching `@key` metadata with an English
`description` that explains the purpose or location of the string:

```json
"loading": "Загрузка...",
"@loading": { "description": "Generic loading text shown on splash screen" }
```

Values are Russian UI copy. Descriptions are always English. Russian Dartdoc in
`lib/core/l10n/` is a generator artifact; do not write it by hand.

## 10. Review Checklist

- Public classes, use cases, Cubits, tokens, and `dpad_v2` API members have a
  `///` summary where required.
- Production comments are in English, except for quoted UI or ticket text.
- Inline comments explain why, instead of paraphrasing code.
- Workarounds and investigation results are anchored to `TV-xxx`.
- TODOs use `// TODO:` or `// TODO(category):`, are actionable, and have no
  author names.
- There is no commented-out code without an explaining TODO.
- `// ignore_for_file:` appears only in generated files.
