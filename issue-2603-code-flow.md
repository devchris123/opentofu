# Issue #2603: how `tofu test` reaches the provider error

Local study notes generated with AI assistance; not intended as an upstream contribution.

Issue: https://github.com/opentofu/opentofu/issues/2603

The reproduction was verified on main commit
`bd2df274bda4b8eda5d49eb89ed6dcc1b5595db4` on September 17, 2026.
Source line numbers below refer to that revision.

## 1. The three configuration files

```text
repro/
├── main.tf           Root module: requires docker/docker v0.4.1
├── main.tftest.hcl   Test: configures docker and runs ./mod
└── mod/
    └── main.tf       Helper module: only outputs a string
```

The test contains a `provider "docker"` block with dummy credentials and a
`run "setup"` block whose `module.source` is `./mod`.

The helper is the root configuration for this run. The top-level module is not
executed by this run. A run without a `module` block would test the top-level
module instead. Running the helper does not recursively execute its own tests.

A `required_providers` block identifies provider software by local name, source,
and version constraint. A `provider` block configures an instance of that
software. Provider requirements belong to each module; they are not inherited
from another module.

## 2. Execution flow

```text
TestCommander
  → TestCommand.Execute
    → loadConfigWithTests
      → LoadConfigWithTests / BuildConfig
        → parse test provider and run blocks
        → buildTestModules: load ./mod as ConfigUnderTest
    → contextOpts / providerFactories
      → build available-provider map from lock file and local cache
    → TestSuiteRunner.Start
      → ExecuteTestFile
        → select ./mod as configuration under test
        → ExecuteTestRun
          → TransformForTest
            → inject test-file provider configuration into ./mod
          → TestFileRunner.validate
            → Context.Validate
              → checkConfigDependencies
                → ProviderRequirements
                  → addProviderRequirements
                    → addProviderRequirementsFromProviderBlock
                      → Module.ProviderForLocalConfig
                        → Module.ImpliedProviderForUnqualifiedType
                          → no local requirement for docker
                          → addrs.ImpliedProviderForUnqualifiedType
                            → NewDefaultProvider: hashicorp/docker
                → HasProvider returns false
                → emit Missing required provider
              → return before building the validation graph
          → return before planning or applying
```

## 3. Source reading guide

### A. Command entry and suite setup

[internal/command/test.go:43](internal/command/test.go#L43): `TestCommander`
connects the CLI command to `TestCommand.Execute`.

[internal/command/test.go:67](internal/command/test.go#L67): `Execute` loads the
configuration and tests, constructs the suite, obtains context options, and
starts the runner.

### B. Parse tests and load the helper

[internal/configs/test_file.go:420](internal/configs/test_file.go#L420):
`loadTestFile` parses test blocks. Provider configurations are stored in
`file.Providers`; runs are stored in `file.Runs`.

[internal/configs/configload/loader_load.go:37](internal/configs/configload/loader_load.go#L37):
`LoadConfigWithTests` loads the root directory with tests, then calls the
configuration-building path.

[internal/configs/config_build.go:140](internal/configs/config_build.go#L140):
`buildTestModules` loads modules selected by test runs. It sets `cfg.Parent = nil`,
rebases module paths, and assigns the result to `run.ConfigUnderTest`. The helper
will behave as an independent root when executed.

### C. Select the configuration for this run

[internal/command/test.go:307](internal/command/test.go#L307):
`TestSuiteRunner.Start` executes test files and invokes cleanup afterward.

[internal/command/test.go:349](internal/command/test.go#L349):
`ExecuteTestFile` iterates runs. Near line 379, it starts with the suite's root
configuration, but selects `run.Config.ConfigUnderTest` when present.
For our run, `config` now represents `./mod`.

### D. Inject test providers — the critical step

[internal/command/test.go:446](internal/command/test.go#L446):
`ExecuteTestRun` validates test/run declarations, builds an evaluation context,
and calls `config.TransformForTest(...)` near line 481. It defers the returned
reset function so these temporary changes can be undone.

[internal/configs/config.go:873](internal/configs/config.go#L873):
`TransformForTest` applies the test transformations, including providers.

[internal/configs/config.go:903](internal/configs/config.go#L903):
`getProviderConfigTransformForTest` constructs the provider configuration map
for the run:

- Start with the providers already configured in the selected module.
- If the run has a nonempty explicit `providers` mapping, copy selected test providers.
- Otherwise, copy all test-file providers (the branch near line 989).
- Assign the resulting map to `c.Module.ProviderConfigs` near line 1016.

Our run takes the copy-all branch. The helper acquires the test's Docker
provider configuration even though it has no Docker resources or data sources.
The transformation does not copy the original root's `required_providers` mapping.

This changes the in-memory configuration only. It does not edit `mod/main.tf`.

### E. Recompute provider requirements in the helper's context

[internal/command/test.go:623](internal/command/test.go#L623):
`TestFileRunner.validate` creates a core context and calls `Context.Validate`.

[internal/tofu/context_validate.go:31](internal/tofu/context_validate.go#L31):
`Context.Validate` checks dependencies before building a validation graph.

[internal/configs/config.go:307](internal/configs/config.go#L307):
`ProviderRequirements` collects requirements from the configuration.

[internal/configs/config.go:505](internal/configs/config.go#L505):
`addProviderRequirements` visits `Module.ProviderConfigs`, including the
newly injected Docker block.

[internal/configs/config.go:566](internal/configs/config.go#L566):
`addProviderRequirementsFromProviderBlock` resolves `provider.Name` using
`c.Module.ProviderForLocalConfig(...)`. Here `c.Module` is the helper.

[internal/configs/module.go:918](internal/configs/module.go#L918):
`ProviderForLocalConfig` delegates to `Module.ImpliedProviderForUnqualifiedType`.
That function, near line 929, looks for the name in this module's
`ProviderRequirements.RequiredProviders` map. The helper has no Docker entry,
so it falls back to the address-level default.

[internal/addrs/provider.go:82](internal/addrs/provider.go#L82):
`ImpliedProviderForUnqualifiedType` calls `NewDefaultProvider` for `docker`.
Near line 97, `NewDefaultProvider` constructs an address with namespace
`hashicorp` and the default registry host. The result is
`registry.opentofu.org/hashicorp/docker`.

### F. Report the missing provider

[internal/tofu/context.go:326](internal/tofu/context.go#L326):
`checkConfigDependencies` collects the requirements and checks
`c.plugins.HasProvider(providerAddr)` for each one.

The available-provider map contains `registry.opentofu.org/docker/docker`,
not `registry.opentofu.org/hashicorp/docker`. The check emits
`Missing required provider` and validation returns early.

This failure happens before graph construction, planning, or applying.

## 4. Why init succeeds but test fails

Address resolution and provider installation are separate operations.

[internal/command/init.go:584](internal/command/init.go#L584): initialization
collects provider requirements from the loaded configuration.

[internal/configs/config.go:510](internal/configs/config.go#L510): during this
collection, test-file provider blocks are examined in the original root's
context. That root declares `docker → docker/docker`, so the address is correct.
The helper has no injected provider configuration yet and adds no requirement.

Initialization then installs the selected provider; see
[internal/command/init.go:971](internal/command/init.go#L971),
`EnsureProviderVersions`.

When `test` starts,
[internal/command/meta.go:377](internal/command/meta.go#L377), `contextOpts`, and
[internal/command/meta_providers.go:220](internal/command/meta_providers.go#L220),
`providerFactories`, build the plugin library from locked, locally installed
providers. The test transformation later introduces the different address.

| Stage | Context used to resolve docker | Result |
|---|---|---|
| init collects the test provider | Original root, with explicit requirement | docker/docker |
| test validates the injected provider | Helper, without explicit requirement | hashicorp/docker |

An installed package can be shared by modules that resolve to the same full
provider address. That does not mean their source-name mappings are inherited.

## 5. Expected behavior we discussed

An unused test provider should not become a requirement that makes the helper
run fail. Simply suppressing all missing-provider errors would be too broad:
those errors remain appropriate when a module actually needs an unavailable
provider.

If the helper actually uses Docker, it should declare its own source mapping to
`docker/docker`. The test can supply the provider configuration and credentials.

## 6. Debugger checkpoints and existing tests

Useful breakpoint locations:

- `ExecuteTestRun`, before and after `TransformForTest`.
- `addProviderRequirementsFromProviderBlock`, when `provider.Name` is `docker`.
- `Module.ImpliedProviderForUnqualifiedType`.
- `checkConfigDependencies`, when checking available providers.

Useful values to inspect:

- `config.Module.SourceDir`: which module is being validated?
- `config.Module.ProviderConfigs`: when does docker appear?
- `config.Module.ProviderRequirements.RequiredProviders`: which source mappings exist?
- `fqn` in `addProviderRequirementsFromProviderBlock`: what address was selected?
- `providerAddr` in `checkConfigDependencies`: what address is unavailable?

Existing tests to read:

- [TestTransformForTest](internal/configs/config_test.go#L857): provider transformation and reset behavior.
- [TestConfigProviderRequirementsInclTests](internal/configs/config_test.go#L234): requirement collection involving test files.

The original CLI reproduction failed with `0 passed, 1 failed`. The control,
which removed only the unused test provider block, passed with `1 passed, 0 failed`.

## 7. Concrete walkthrough of the reproduction

See [issue-2603-concrete-trace.md](issue-2603-concrete-trace.md) for the complete
loader call chain and snapshots of the objects created from our three files.
It also covers the early `resolveProviderTypesForTests` pass: that pass assigns
the unused test provider a default type, before the later requirement collection
independently resolves its name in the helper and triggers the missing-provider error.
