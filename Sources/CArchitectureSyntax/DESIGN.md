# CArchitectureSyntax

## Purpose and Scope
Native platform adapter module. Parent: [system](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Declare pinned tree-sitter grammar ABI symbols linked by skeleton parser products; parsers own all tree memory.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../ArchitectureCore/DESIGN.md) | used by | Native ABI boundary | Checked ownership and scope | No pointers escape their owning operation |

## Architecture
```text
Swift owner -> C ABI -> fixed native implementation
```

## Contracts and Invariants
The Swift owner validates lengths, lifetime and resource release. This module does not weaken Sendable or synchronization by target. Unsupported targets are outside the macOS package contract.

## Verification and Change Impact
Compile/link and behavioral tests use the actual macOS symbols. Recheck the owning Swift module on ABI changes.
