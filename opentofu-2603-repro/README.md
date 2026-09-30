# OpenTofu issue #2603 reproduction

Original report: https://github.com/opentofu/opentofu/issues/2603

The root configuration requires `docker/docker` 0.4.1. The test defines a Docker
provider but runs only `./mod`, which has an output and uses no providers.
The reported bug is resolving the unused test provider as `hashicorp/docker`.

## Run

```bash
cd /home/testchris/opentofu-2603-repro
./run.sh
```

The script runs the locally built main-branch binary, initializes providers, then
runs the test with trace logging. It preserves `version.log`, `init.log`,
`test.log`, `trace.log`, and `test.exit-code`. It returns the test exit status.
Initialization needs internet access to download the provider. The credentials
in the fixture are the report's dummy values; no real Docker account or Docker
daemon is needed to exercise the reported provider-resolution error.

Do not run `apply` in this directory: the reproduction uses `tofu test`, whose
only run targets the output-only helper module.

## Control

`control/` differs only by removing the provider block from `main.tftest.hcl`.

```bash
./bin/tofu -chdir=control init -input=false -no-color
./bin/tofu -chdir=control test -no-color
```

## Rebuild after source edits

```bash
cd /home/testchris/opentofu
go build -o /home/testchris/opentofu-2603-repro/bin/tofu ./cmd/tofu
```

`REVISION` records the original tested source commit. The source checkout was
clean and matched upstream main when fetched on 2026-09-17:
`bd2df274bda4b8eda5d49eb89ed6dcc1b5595db4` (commit date 2026-09-16).
Go selected the 1.27.1 toolchain required by this revision's go.mod.

## Verified result (2026-09-17)

The issue still reproduces on the recorded upstream-main commit, reporting
OpenTofu v1.14.0-dev on linux_amd64.

- Original fixture: `init` succeeds and installs `docker/docker` v0.4.1.
- Original fixture: `test` exits 1 with `Missing required provider`, requesting
  `registry.opentofu.org/hashicorp/docker`; `0 passed, 1 failed`.
- Control fixture: `init` succeeds and `test` exits 0; `1 passed, 0 failed`.

See `test.log`, `trace.log`, and `control/test.log` for the captured evidence.
The source checkout remains clean. A useful investigation starting point is
`internal/configs/config.go`, function `getProviderConfigTransformForTest`,
which copies all test-file provider configurations into the run's configuration
when no explicit provider mapping is supplied.
