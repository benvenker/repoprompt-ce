# Pass 2 Regression Alerts

No regressions over 50 points were identified.

One validation caveat is environmental rather than behavioral: the Docker-built
debug binary under `.build-linux/debug/rpce-headless` does not run directly on
the host because Swift runtime libraries are not installed there. This is the
known Linux workflow documented in `AGENTS.md`; use Docker smokes or the static
installer.
