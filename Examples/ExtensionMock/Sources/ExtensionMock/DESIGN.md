# ExtensionMock executable

## Purpose and Scope
Own the executable composition root. Parent: [package](../../DESIGN.md). No child components.

## Responsibilities and Boundaries
Separately launched, bounded simulation using the public extension SDK. Consume registered session contracts; do not add a host-privilege or process-launch bypass.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Explicit launch and ownership | Process composition | No automatic Explorer launch |
| [SDK](../../../../Sources/ArchitectureClient/ExtensionProvider/DESIGN.md) | depends on | Session, input and publication API | Runtime I/O | Errors remain explicit |

## Architecture
```text
Entrypoint -> pending approval -> approved Client -> capture/publication -> shutdown
```

## Contracts and Invariants
Source input is fixed and validated. Provider-reported values remain external.

## State, Ownership, and Lifecycle
Invocation-local values and actor-owned mock tasks hold state. Shutdown cancels and awaits owned mock work before disconnect. The reader probe releases its captured lease through the existing Invar adapter.

## Failure, Concurrency, and Constraints
Native macOS only; no isolation branch. All I/O failures are reported. Only the example mock simulates work; the Invar probe does not invoke backends.

## Verification and Change Impact
The bounded [native integration](../../../../Tools/extension-integration.py) exercises real daemon/HTTP responses and process cleanup.
