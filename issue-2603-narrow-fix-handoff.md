# Fresh-session handoff: issue #2603

## Task

Investigate a narrower fix for [OpenTofu issue #2603](https://github.com/opentofu/opentofu/issues/2603). Before a test run copies provider configurations from its `.tftest.hcl` file into an alternate module selected by `run.module`, determine which provider configurations that module actually needs. Avoid copying an unused test-file provider configuration into the alternate module. Preserve the behavior of test runs that do need a test-file provider, including aliases and explicit `providers` mappings. Analyze the inferred providers **before** changing the module's provider configurations.

This is an investigation and implementation task; the exact selection rule and implementation point are still open. Assess the existing inference and validation paths rather than assuming that one existing provider list already represents every dependency.

## Minimal problem

The local reproduction is in `opentofu-2603-repro/`:

- The root module requires `docker/docker` v0.4.1 and has a Docker data source.
- `main.tftest.hcl` defines a `provider "docker"` configuration and a `run "setup"` selecting `./mod`. The run has **no explicit** `providers` mapping.
- `./mod` contains only a constant output. It does not use Docker.

Without the issue fix, `tofu init` installs `docker/docker`, but `tofu test` copies the test-file Docker configuration into `./mod`. Validation then treats that block as a dependency of the helper. Because the helper has no Docker requirement, it infers `hashicorp/docker` and fails with `Missing required provider`. The desired outcome for this minimal reproduction is a passing test without making the unused Docker configuration a dependency of the helper.

An explicit `providers` mapping and an implicit copy are different paths. The reproduction uses the implicit path; absence of a run-level mapping does **not** mean the test file has no provider configuration.

## Code orientation

- `internal/configs/config.go`: `getProviderConfigTransformForTest` currently copies every test-file provider and mock into the selected configuration when `run.Providers` is empty. With an explicit mapping, it copies only mapped configurations.
- `internal/configs/config.go`: `resolveProviderTypes`, `resolveProviderTypesForTests`, and `ProviderRequirements`/`addProviderRequirements` provide related but different views of providers. In particular, inspect what each includes from declarations, provider blocks, resources, child modules, and tests before using it as the pre-copy dependency signal.
- `internal/configs/provider_validation.go`: test provider matching and alias validation.
- `internal/configs/config_build.go`: `buildTestModules` loads an alternate run module as a separate configuration for the run.

Commit `5e78389a97` is prior work on this issue and can be read for context, but it is **not** the proposed design for this new approach. At handoff time the checkout is `devchris/2603/fix-provider-testing-issue-narrow` at `be20ff3b96`; `5e78389a97` is not in this branch's history. The working tree has no tracked modifications. The reproduction and manual fixtures are local untracked files.

## Behavioral boundaries to verify

- The original output-only reproduction passes, while a helper that genuinely uses a test-file provider still receives the right configuration.
- A helper's own provider configuration and provider identity remain intact when the test file does not select or need them. `opentofu-2603-repro/manual-regression/19_preexisting_no_test_provider/` is a useful guardrail.
- Explicit mappings, renamed local names, aliases, mocks, ordinary root-module runs, sequential runs, and invalid provider references retain their intended behavior.
- `opentofu-2603-repro/manual-regression/` contains reusable exploratory fixtures. Their runner's expected outcomes reflect the earlier approach; review expectations before treating the suite as a specification for this narrower behavior.

## Decisions to settle

1. What counts as a helper dependency for the implicit path: a `required_providers` declaration alone, an existing `provider` block, actual resource/data/ephemeral use, descendant-module use, or some combination? Consider provider use needed from prior test-run state and cleanup as well as the current configuration.
2. Should an **explicit** run-level `providers` mapping always be honored, even when the helper has no otherwise inferred use for that provider? What should `providers = {}` mean?
3. How should selection work for aliases, renamed local names, mock providers, and providers with `for_each`? What diagnostic should appear when a requested mapping is absent or incompatible with the helper's provider identity?
4. Should an unused test-file provider block still be schema-checked or otherwise diagnosed, even if it is not copied into this particular helper run? Decide whether skipping it changes expected validation behavior.

These are product/compatibility questions, not settled choices. Use focused unit tests and the CLI reproduction to establish the intended rule before broadening the change.

Repository policy: read `CONTRIBUTING.md` and `AGENTS.md` before work. OpenTofu does not accept LLM-assisted pull requests; keep any AI-assisted changes local and do not open a PR.
