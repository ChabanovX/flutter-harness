# ADR 0004: Modular composition root

## Status

Accepted.

## Context

A single large DI file preserves explicit construction order but becomes hard to review and easy to break.

## Decision

Expose one public composition entry point and split registration into core and feature modules. Keep registration free of runtime side effects; start listeners/services in a separate bootstrap phase.

## Consequences

Dependency ownership and lifetimes remain explicit while each module is locally understandable and testable.
