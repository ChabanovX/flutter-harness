# Error policy

## Invariant

Presentation must never receive `DioException`, HTTP status codes, database exceptions, or plugin exceptions.

Data-layer repository implementations catch operational infrastructure exceptions and convert them through a feature-owned failure mapping policy before returning an `AppResult<T>`. Programming `Error`s are rethrown rather than being disguised as recoverable product failures.

```text
Dio/database/plugin error
          ↓
 FeatureFailureMapper.map
          ↓
       AppFailure
          ↓
     AppResult<T>
          ↓
   application/Cubit
```

The default mapping policy is deterministic and stateless, so represent it as a non-instantiable Dart namespace (`abstract final class` with static methods) and call it directly from the data boundary. Do not register or inject mapper objects merely to replace them in tests.

Use an injected mapper contract only when at least one real architectural requirement needs polymorphism: composition selects among multiple production policies at runtime, or mapping owns state, dependencies, or side effects. A hypothetical alternative or a test double is not sufficient justification.

## Failure taxonomy

Start small and add categories only when product behavior differs:

- network unavailable/timeout;
- unauthorized/session expired;
- validation/rejected input;
- not found;
- server/unavailable;
- cache/persistence;
- unexpected.

Failures may include a stable code and safe user-facing context. Raw causes and stack traces are diagnostic metadata, not UI copy.

## Testing requirement

For every new repository integration, include a contract test using the real DTO parser, production mapping policies, and repository implementation over a deterministic datasource or transport adapter. Do not inject a fake mapper to manufacture the expected failure. After the concrete adapter exists, add at least one adapter-level test that exercises its real error shape. At least one test must prove that a transport/persistence exception becomes the exact `AppFailure` expected by presentation.
