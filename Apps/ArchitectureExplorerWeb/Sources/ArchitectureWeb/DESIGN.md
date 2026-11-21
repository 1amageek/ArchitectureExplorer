# ArchitectureWeb

## Purpose and Scope
Own browser page resources within the [Web package](../../DESIGN.md).
Children:
- [Page](Page/DESIGN.md)

## Responsibilities and Boundaries
Use the package's public contracts and immutable Client responses. Source access and graph meaning belong to the headless daemon.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Web package](../../DESIGN.md) | parent | Authenticated bounded explorer | Composition | Preserve process and dependency isolation |

## Architecture
```text
Caller -> module composition -> owned components -> immutable result
```

## Contracts and Invariants
Retain snapshot/provenance and explicit incompleteness. Never report rejected authentication, unavailable source or failed workers as successful empty data.

## Verification and Change Impact
Tools/web-integration.py and browser behavioral probes cover the public paths. Review the parent when changing authentication, input gestures or lifetimes.

Live workspace entry and Home use the Context overview. Source views remain accessible through the level selector.
