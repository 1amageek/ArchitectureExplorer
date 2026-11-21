# ArchitectureExplorer work rules

- Communicate with the user in Japanese and show relationships with a concise diagram or table.
- Write source code, comments and documentation comments in English.
- Keep ArchitectureExplorer independent of swift-formal and verifier orchestration.
- Keep headless and Web manifests/processes separate; Web depends on the root.
- Read the owning DESIGN.md and actual implementation/callers before editing.
- Preserve immutable snapshot identities, producer/scope replacement, evidence and explicit incompleteness.
- When changing source dependency navigation, exercise the actual entry point and check the identity, direction and evidence of shared references across views of the same snapshot. See the [graph query design](Sources/ArchitectureGraph/Query/DESIGN.md).
- Validate real behavior, including failures, cancellation and owned process cleanup. Give every test command a timeout.
- Run Tools/build.py for the Web target's fixed macOS 27 baseline.
- Track unfinished SPEC acceptance criteria in PROGRESS.md and mark incomplete production branches with FIXME(INCOMPLETE_IMPLEMENTATION).
- Keep unrelated existing work untouched. Review branch/message before coherent local commits. Push only to a configured upstream when the task owns all included commits. Publishing, tags, releases and deployment require explicit authorization.
