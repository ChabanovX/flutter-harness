# Reference feature

Generate the canonical vertical slice:

```bash
dart run tool/harness.dart scaffold feature notifications --entity notification
```

The output demonstrates:

```text
NotificationDto
  → NotificationMapper
  → Notification
  → NotificationsRepositoryImpl
  → GetNotifications
  → NotificationsCubit
  → NotificationsState
  → NotificationsPage
```

It also generates:

- mapper test;
- use-case test;
- repository error-normalization contract test;
- Cubit state-sequence test;
- widget smoke/state test when enabled;
- a GetIt registration module.

The concrete HTTP datasource and router registration are intentionally left explicit. Different projects use Dio, Retrofit, GraphQL, gRPC, local-first stores, or P2P adapters; the architectural boundary is stable while the adapter is project-specific.

Before accepting a new pattern, update one canonical feature and this document rather than allowing multiple competing conventions.
