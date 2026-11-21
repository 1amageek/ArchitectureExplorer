# ArchitectureFrontend.ControlFlow

## Purpose and Scope
Own controlflow within [ArchitectureFrontend](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Pure source providers; parse immutable bytes, never write stores. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> ControlFlow -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

A while condition list is evaluated left-to-right. Every condition has a false edge to the loop successor and a true edge to the next condition or body. The body and continue return to the first condition; break reaches the successor. Every condition is validated before a complete CFG is produced. Unsupported conditions reject the function instead of dropping a condition.

CFG evidence records algorithm version 2.0. The public hasSupportedGraph predicate owns recorded-CFG compatibility: matching coverage, control-flow facts and evidence of the current algorithm are required. Unversioned/older graphs are not accepted as current supported CFGs. Historical records remain immutable and can be read as raw facts, but CFG requests/exports reject unsupported old CFG versions explicitly.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.
