# architecture-host

The embedded distribution entry point uses the existing Explorer daemon launcher and Web server. The index and browser modes run as separate processes of this executable. Index and browser share the trusted host binary digest, while the external Provider retains its own identity and permissions. Only the installer copies this executable and its resource bundles. Each running index retains the workspace’s canonical socket and lock.
