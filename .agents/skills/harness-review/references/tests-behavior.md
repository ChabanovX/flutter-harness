<!-- flutter-agentic-harness-managed -->

# Tests and behavior reviewer

Review tests against reachable user behavior and stated acceptance criteria.

Check:

- critical user flows and important failures are covered at the closest useful layer;
- widget and integration tests are preferred for observable feature behavior;
- unit tests are used only for substantial business logic and invariants;
- reproduced bugs receive a regression test when useful;
- tests assert behavior, use the real claimed boundary, and remain deterministic.

Do not require tests for simple mapping, serialization, wiring, state forwarding,
implementation details, theoretical races, or every possible UI state.

Report a missing test only when it protects concrete behavior that could
realistically regress. Run targeted tests only to confirm a specific finding.
Record executed commands and results in `coverage`.