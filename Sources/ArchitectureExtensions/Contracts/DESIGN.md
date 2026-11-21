# ArchitectureExtensions.Contracts

## Purpose and Scope
Own immutable manifest, permission, binding, registration, action, run, contribution and input-manifest values. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Validate bounded declarative values without I/O. Runtime authorization and publication ordering belong to [Service extensions](../../ArchitectureService/Extensions/DESIGN.md).

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public library composition | Dependency direction | No runtime state |
| [Core values](../../ArchitectureCore/Values/DESIGN.md) | depends on | JSONValue and CanonicalJSON | Serialization and SHA-256 | Manifest digest differs from file SHA-256 |
| [IR snapshots](../../ArchitectureIR/Snapshots/DESIGN.md) | depends on | Immutable Snapshot | Input identity | Dependency completeness is unknown |

## Architecture
```text
Manifest -> supported profile/schema validation
Snapshot -> InputManifest -> ExtensionBinding
Binding + registered action + arguments -> fingerprint
Binding + contributions -> immutable PublicationManifest
```

## Contracts and Invariants
Wire fields match [Schemas](../../../Schemas) and the [API reference](../../../Documentation/EXTENSIONS-API.md). Input files and metadata are separately named digest domains. Absent dependency evidence remains `unknown`. Action fingerprints use sorted-key CanonicalJSON and SHA-256 over the stable request/provider/action/schema/effect/binding/arguments/deadline fields; session, token and transport identity are excluded. Bindings retain exact EntityID/FactID and never transfer by display name.

Argument schemas reject unsupported keywords, references and unbounded nesting: depth below eight, at most 64 properties/enumeration choices, 256 array items and 4096 string bytes. Manifests are at most 64 KiB with 16 views/actions. Contributions are at most 1 MiB; view data at most 64 KiB. Graphs are bounded to 500 nodes/1500 edges with distinct, Provider-prefixed identities and valid endpoints. View data is literal, with typed bounded table/timeline/key-value/artifact structures. No executable markup, command or URL is a rendering primitive.

## Verification and Change Impact
[ExtensionTests](../../../Tests/ArchitectureTests/ExtensionTests.swift) covers actual validation failures, identity conflicts and consumers. [Native integration](../../../Tools/extension-integration.py) validates SDK-produced wire values against JSON schemas and exercises fixed-byte capture. Wire changes recheck the parent module and all direct consumers.

## Canvas authority
`canvas.read` and `canvas.control` are separately approved Provider permissions. They expose shared presentation sessions only; neither grants verification execution, source mutation or extension approval. Existing grants gain neither permission implicitly.
Presentation mutations return acknowledged session data and therefore require both permissions. Read-only access requires only `canvas.read`.

A publication manifest may carry a provider-authored attemptDiagnostic of up to 1024 UTF-8 bytes. Its text is part of the immutable manifest digest. The provider chooses text suitable for public display.
