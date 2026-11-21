# Local safety

Default analysis reads saved source and never evaluates manifests or launches language servers. Explicit invocation-level workspace trust is required before official metadata or a selected local semantic process. Repository configuration cannot grant trust. Cargo metadata is offline; SwiftPM automatic resolution is disabled. Runtime dependencies and JS assets are installed/bundled ahead of time, with no CDN or telemetry.

Source roots are canonicalized. Traversal paths, external symlink destinations and source requests without a matching entity/digest are rejected. Historical source bodies are not retained; a stale inspector request fails instead of reading unrelated disk content. Subprocesses use executable/argument arrays without a shell. Source comments, labels, annotations and external results are untrusted data, never tool instructions. HTML text uses textContent; standalone exports encode graph data as base64 and escape SVG/Mermaid labels.

The Web listener binds only 127.0.0.1. Exact Host and Origin are checked. A 90-second one-use URL-fragment token creates a host-only HttpOnly/SameSite=Strict session. HTTP loopback omits Secure; HTTPS/external binding are unsupported. Web APIs are read-only; session bootstrap validates Origin and a one-use token. WebSocket authentication occurs before upgrade and refused channels close. The native adapter correction is explained in ADR 0004.

See web-security-results.json for actual authentication/refusal checks. This is not a claim that fuzzing, every crash-recovery scenario, arbitrary malicious LSP servers or all denial-of-service cases have been validated.

Loopback session cookie names include the listening port, allowing two helpers to remain authenticated in one browser jar. Each helper still validates its own cookie value and exact Host/Origin. LSP subprocess backpressure is handled through bounded nonblocking writes/reads and cancellation-safe owned cleanup; process-wide SIGPIPE policy is unchanged. These paths have real non-reading/closed-input child-process regression checks, not just mocked transport tests.
