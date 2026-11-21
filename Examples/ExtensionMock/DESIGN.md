# ExtensionMock

## Purpose and Scope
Separately launched, bounded simulation using the public extension SDK. Parent: [Explorer system](../../DESIGN.md). Child: [executable module](Sources/ExtensionMock/DESIGN.md).

## Responsibilities and Boundaries
This is an explicitly launched integration artifact, outside the Explorer production dependency graph. It owns its test process and local state; Explorer does not launch it.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client extension SDK](../../Sources/ArchitectureClient/ExtensionProvider/DESIGN.md) | depends on | Approved session API | External integration | Explicit approval required |
| [Executable](Sources/ExtensionMock/DESIGN.md) | child | Entrypoint lifecycle | Local process | Cleanup is awaited |

## Architecture
```text
Explicit user/test launch -> executable -> Client SDK -> shared daemon
```

## Contracts and Invariants
Use the fixed aex-1.3 profile. Test output does not establish verification success.

## Verification and Change Impact
[Native integration](../../Tools/extension-integration.py) builds and runs this consumer independently. Recheck SDK behavior after changes.
