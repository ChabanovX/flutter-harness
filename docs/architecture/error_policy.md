# Error policy

## Invariant

Presentation must never receive `DioException`, HTTP status codes, database exceptions, or plugin exceptions.

Data-layer repository implementations catch operational infrastructure exceptions and convert them through a `FailureMapper` before returning an `AppResult<T>`. Programming `Error`s are rethrown rather than being disguised as recoverable product failures.

```text
Dio/database/plugin error
          ↓
      FailureMapper
          ↓
       AppFailure
          ↓
     AppResult<T>
          ↓
   application/Cubit
```

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

For every new repository integration, include a contract test using the real DTO parser, mapper, and repository implementation over a deterministic datasource or transport adapter. After the concrete adapter exists, add at least one adapter-level test that exercises its real error shape. At least one test must prove that a transport/persistence exception becomes the exact `AppFailure` expected by presentation.
