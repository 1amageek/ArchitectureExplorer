# Actual Invar reader integration

This optional consumer-side probe builds against the sibling `Invar` checkout and uses its real `ExplorerSnapshotReader` with an approved session Client. It captures complete source/inventory, then disconnects. It does not run Invar verification backends and does not modify the Invar checkout.

Build with `python3 Tools/run.py 300 swift build --package-path Examples/InvarReaderProbe`. The normal `Tools/extension-integration.py` detects the resulting executable and tests its approval/capture path. Explorer's root dependency graph remains independent of Invar and Formal.
