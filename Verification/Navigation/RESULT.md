# Destination-first navigation

The model formalizes Page/SPEC.md NAV01 and NAV04 independently of JavaScript. Three destination generations, starts, success/failure replies and Back actions are explored. The safe protocol commits a destination before its read and accepts only replies for the current generation. TLC checks DestinationBeforeRead, CurrentResultOnly and NoOldResultWhileLoading over 106 distinct reachable states. Permitting stale replies violates CurrentResultOnly; its retained counterexample is the negative control.

Run `python3 Verification/Navigation/verify.py --toolchain <pinned-toolchain-directory>` with the existing verified TLA+ 1.7.4 and JRE 21 toolchain. The model has explicit finite bounds. It does not prove JavaScript translation, browser rendering, provider execution or general liveness.

Production controller and page tests delay the destination paint, session reads, source resolution and file bytes. They check synchronous destination commitment, failure/retry, unchanged history on retry, Back and rejection of late success/failure. Existing verification action tests preserve confirmation, exact snapshot binding, partial results and source evidence. Actual browser checks cover the served page and navigation controls separately.
