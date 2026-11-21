# External Provider simulation

This separately launched example validates the public SDK and never claims real verification. It captures original source bytes, publishes one annotation/graph/table/timeline bundle, receives confirmed actions and simulates cancellable work. The root Explorer daemon never launches this executable.

```sh
python3 Tools/build.py
python3 Tools/run.py 300 swift build --package-path Examples/ExtensionMock
.build/debug/architecture index --workspace /absolute/workspace
.build/debug/architecture explore --workspace /absolute/workspace
Examples/ExtensionMock/.build/debug/ExtensionMock /absolute/workspace /absolute/private-provider-state
```

Open Extensions and approve the displayed executable/permissions. Use a dedicated test workspace. State holds the secret resume credential and durable action ledger, and must not be committed or shared. To simulate an operation, choose “Simulate analysis”, review the exact binding/arguments, and confirm. Cancel expects the original request/job/run IDs shown in the job state API.

Run the bounded automated checks with `python3 Tools/run.py 120 python3 Tools/extension-integration.py`. See [API](../../Documentation/EXTENSIONS-API.md). The optional [Invar reader probe](../InvarReaderProbe) needs the sibling Invar checkout; it does not add a root Explorer dependency.
