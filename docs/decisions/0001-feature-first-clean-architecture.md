# ADR 0001: Feature-first Clean Architecture

## Status

Accepted.

## Context

Global `data/`, `domain/`, and `presentation/` directories become difficult to navigate and give coding agents too much unrelated context.

## Decision

Organize production behavior under `features/<feature>/`, with domain, application, data, and presentation inside each feature. Shared concepts must earn placement in `shared/`; generic infrastructure belongs in `core/`.

## Consequences

Feature changes are locally discoverable and changed-test selection is reliable. Direct cross-feature imports are restricted and coordination moves to explicit contracts or app-level composition.
