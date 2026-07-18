# Contributing

- **No direct commits to `main`** — branch → PR → green checks → merge.
- **Before you open a PR**, run the same gates CI does — they must pass:

  ```sh
  bash -n edda        # syntax check
  shellcheck edda     # lint (the script is clean; only SC2059 is disabled, file-level)
  bash test/run.sh    # the throwaway-vault test harness
  ```

  New behavior ships with a test in `test/run.sh`, in the same PR.
- **AgentGate runs on every PR** — `secrets` + `dangerous_patterns` are errors that block. Note the
  `dangerous_patterns` rule scans added diff lines *including prose*, so avoid spelling risky code
  tokens out in docs.
- Never commit secrets (`.env`, keys are gitignored).
