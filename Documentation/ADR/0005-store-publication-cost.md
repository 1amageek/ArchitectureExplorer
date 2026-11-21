# Reuse serialized snapshots when indexing SQLite

The Medium cold-index probe exceeded the IPC deadline. A three-second `sample` of the live daemon showed publication spending most CPU time repeatedly invoking Foundation JSONEncoder for each normalized entity/fact row and preparing individual statements. The snapshot had already been serialized canonically for its atomic history record.

Keep that serialization as the single transfer-value encoding. SQLite JSON1 inserts normalized rows and checks identity registry conflicts in bulk within the same transaction. Do not weaken graph validation, producer ownership, FULL synchronous commit or history retention. The Store actor retains its latest validated immutable snapshot instead of decoding it again before each publication. Graph queries read the last published snapshot while reconciliation runs separately; explicit index requests wait for reconciliation. Scanner reads the canonical root-validated URL once rather than resolving the same path a second time.

Behavioral regression must cover rollback/generation checks and incremental/fresh equivalence. Performance is measured again through the compiled CLI with the same input hashing and persistence enabled; no claim is made from the sample alone.
