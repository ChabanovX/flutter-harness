# ADR 0002: Explicit navigation authority and projection

## Status

Accepted; replaces the original router-only decision.

## Context

Applications need one durable source of page location and history across normal pages, fullscreen flows, app shells, deep links, restoration, browser history, and system Back. Feature-owned navigation calls and page/provider composition scattered through widgets make that ownership impossible to verify.

Some projects model navigation workflows in Bloc state and need the router to project that state. Others rely on a router's native location/history model. Both require the same explicit composition and feature boundaries.

## Decision

Every project selects one navigation authority in harness configuration:

- `bloc_projection` is the default. A navigation Bloc under `app/navigation` solely owns navigation state/history. The router under `app/router` reads that state and projects pages and URLs without becoming a second authority.
- `router` is opt-in. The configured router directly owns location/history.

Feature presentation declares narrow typed navigation ports. App composition implements and injects them through the selected authority. Project pages/screens and Bloc providers are created only in configured composition paths. Durable Back is an authority intent; local `Navigator.pop`/`maybePop` is limited to transient UI.

## Consequences

Navigation authority can be selected without weakening feature isolation or provider lifetime rules. Static checks can block direct router dependencies, durable imperative navigation, page switching, and provider placement outside composition. Behavioral correctness—including hidden route stacks, transient-pop intent, deep links, restoration, system Back, and custom wrappers—remains an explicit review responsibility.

Existing router-owned projects migrate by setting `authority: router`. New installations use `bloc_projection`.
