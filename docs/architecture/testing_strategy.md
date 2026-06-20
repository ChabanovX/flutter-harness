# Testing strategy

## Test pyramid

### Pure unit tests

Test domain invariants, value objects, mappers, and application orchestration.

### Cubit tests

Test state sequences, retries, stale-response handling, pagination guards, optimistic rollback, and cleanup.

### Repository contract tests

Use the real DTO mapping and repository implementation over a fake/mock transport or persistence adapter. Do not replace the repository with a mock in every test.

### Widget scenario tests

Cover loading, loaded, empty, failure, retry, and relevant interaction states with deterministic dependencies, fixed locale/theme, and fixed screen size.

### Integration journeys

Keep a small set of high-value user journeys. These are slower and should not duplicate every widget/unit assertion.

## Verification modes

`verify --changed` selects tests for changed feature paths. Changes to app/core/shared/tooling or dependency files trigger the full suite. Documentation-only changes skip tests.

`verify --all` runs formatting, analysis, architecture checks, the entire test suite, and configured extra commands. CI should use the same command developers use locally.

## Generated code

When the app uses code generation, add deterministic generation and a `git diff --exit-code` check to `verification.extra_commands`.
