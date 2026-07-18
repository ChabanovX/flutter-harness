# Testing strategy

## Test pyramid

### Pure unit tests

Test domain invariants, value objects, production mapping policies, and application orchestration.

### Cubit tests

Test state sequences, retries, stale-response handling, pagination guards, optimistic rollback, and cleanup.

### Repository contract tests

Use the real DTO and failure mapping policies with the repository implementation over a fake/mock transport or persistence adapter. Fake the effectful boundary, not deterministic mapping logic. Do not replace the repository with a mock in every test.

### Widget scenario tests

Cover loading, loaded, empty, failure, retry, and relevant interaction states with deterministic dependencies, fixed locale/theme, and fixed screen size.

### Integration journeys

Keep a small set of high-value user journeys. These are slower and should not duplicate every widget/unit assertion.

## Test comments

Use comments in tests to document behavior contracts and regression risks, not to paraphrase assertions.

Large Cubit, navigation, cache, and integration test files may start with a short scenario matrix. Inline comments should explain async setup, race conditions, platform assumptions, or why a fake/stub is shaped a certain way. Avoid comments like "tap the button" or "expect success" when the code already says that.

## Verification modes

`verify --changed` selects tests for changed feature paths. Changes to app/core/shared/tooling or dependency files trigger the full suite. Documentation-only changes skip tests.

`verify --all` runs formatting, analysis, architecture checks, the entire test suite, and configured extra commands. CI should use the same command developers use locally.

## Generated code

When the app uses code generation, add deterministic generation and a `git diff --exit-code` check to `verification.extra_commands`.
