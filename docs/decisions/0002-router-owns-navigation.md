# ADR 0002: Router-owned navigation

## Status

Accepted.

## Context

The source Smart TV architecture needed a custom content-screen state machine for focus continuity and nonstandard overlays. General mobile, desktop, and web applications need deep links, nested routes, restoration, and browser history.

## Decision

The router is the sole source of truth for route location and history. Session state may trigger redirects. Feature state does not duplicate the route stack.

## Consequences

Deep links and platform history remain native to the routing system. Workflow Cubits may coordinate multi-step behavior but cannot act as a parallel router.
