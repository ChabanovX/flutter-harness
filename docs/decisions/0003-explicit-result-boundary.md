# ADR 0003: Explicit result boundary

## Status

Accepted.

## Context

Wrapping an application exception inside a transport exception allows raw infrastructure errors to leak into Cubits, while mocked tests can hide the mismatch.

## Decision

Repository ports return `AppResult<T>`. Repository implementations catch transport/persistence exceptions and map them to `AppFailure` before returning.

## Consequences

Failure handling is visible in types and exhaustive switches. Contract tests can prove the real adapter-to-presentation boundary.
