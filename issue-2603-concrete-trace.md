# Issue #2603: tracing our three files

Local AI-assisted study notes, not an upstream contribution.
Source revision: bd2df274bda4b8eda5d49eb89ed6dcc1b5595db4.
This is a source-code walkthrough using the verified CLI reproduction, not a
recording of a debugger session. Object snapshots below are simplified.

## 1. Inputs on disk

Our working directory is `opentofu-2603-repro/`.

`main.tf`:

```hcl
terraform {
  required_providers {
    docker = {
      source  = "docker/docker"
      version = "0.4.1"
    }
  }
}

data "docker_hub_repository" "example" {
  namespace = "library"
  name      = "memcached"
}
```

`main.tftest.hcl`:

```hcl
provider "docker" {
  username = "user"
  password = "password"
}

run "setup" {
  module {
    source = "./mod"
  }
}
```

`mod/main.tf`:

```hcl
output "password" {
  value = "pass"
}
```

Assume `tofu init` has succeeded and installed `docker/docker` v0.4.1.
We now run `tofu test` from the reproduction directory.

## 2. From test.go to parsing the files

Follow this exact chain:

```text
TestCommand.Execute                         internal/command/test.go:67
  → Meta.loadConfigWithTests                internal/command/meta_config.go:56
    → lazyLoader.LoadConfigWithTests        internal/configs/configload/lazy.go:129
      → loader.LoadConfigWithTests          internal/configs/configload/loader_load.go:37
        → Parser.LoadConfigDirWithTests     internal/configs/parser_config_dir.go:79
```

`TestCommand` embeds `Meta`, so `c.loadConfigWithTests(...)` invokes the method
on that embedded value. `configLoader()` returns an interface; the lazy loader
initializes the concrete loader and forwards the call.

`Parser.LoadConfigDirWithTests` discovers files in the root and test directory.
For our fixture, its relevant lists are:

```text
primaryPaths = [main.tf]
overridePaths = []
testPaths = [main.tftest.hcl]
```

It does not merge `mod/main.tf` into the root module. Subdirectories are separate
modules and are loaded when referenced.

### 2a. main.tf

`p.loadFiles(primaryPaths, false)` loads the regular configuration file.
Its declarations will contribute these entries to the root module:

```text
ProviderRequirements.RequiredProviders["docker"]:
  source/type = registry.opentofu.org/docker/docker
  version constraint = 0.4.1

DataResources:
  docker_hub_repository.example

ProviderConfigs:
  empty — main.tf contains no provider configuration block
```

Loading the data source declaration does not query Docker Hub.

### 2b. main.tftest.hcl

The next relevant call is `p.loadTestFiles(path, testPaths)`:

```text
Parser.loadTestFiles             parser_config_dir.go:308
  → Parser.LoadTestFile(path)    parser_config.go:46
    → Parser.LoadHCLFile(path)   reads/parses HCL syntax
    → loadTestFile(body)         test_file.go:420
```

`loadTestFile` loops over the parsed blocks:

- For `provider "docker"`, it calls `decodeProviderBlock` and stores the result
  in `tf.Providers["docker"]`. The credentials remain configuration expressions.
- For `run "setup"`, it calls `decodeTestRunBlock` and appends the run to `tf.Runs`.
  The nested module block records the source `./mod`.

At this point the relevant test object looks like:

```text
TestFile:
  Providers["docker"] = provider configuration with username/password
  Runs[0]:
    Name = "setup"
    Module.Source = "./mod"
    Providers = empty (no explicit providers mapping in this run)
    ConfigUnderTest = not attached yet
```

`NewModuleWithTests` in [module.go:167](internal/configs/module.go#L167)
combines the regular configuration files into the root module and assigns
`mod.Tests = testFiles`.

The provider configuration belongs to `root.Module.Tests["main.tftest.hcl"]`.
It has not been inserted into the helper module yet.

## 3. Load mod/main.tf as a separate configuration

Back in `loader.LoadConfigWithTests`, the next step is `l.loadConfig(...)`,
which calls `configs.BuildConfig`.

[buildTestModules](internal/configs/config_build.go#L140) visits our setup run,
sees its module source, and loads `./mod` using the module loader.

`mod/main.tf` contributes only:

```text
Outputs["password"] = expression "pass"
ProviderRequirements.RequiredProviders = empty
ProviderConfigs = empty
ManagedResources = empty
DataResources = empty
```

The test module is initially loaded using a synthetic path such as
`test.main.setup`. Then `buildTestModules` sets its parent to nil and rebases
its paths so it behaves as a root configuration. It assigns this configuration
to the setup run's `ConfigUnderTest` field.

The relationship is now:

```text
root Config (main.tf)
  Module.Tests["main.tftest.hcl"]
    Providers["docker"] = test provider configuration
    Runs[0] (setup)
      ConfigUnderTest → helper Config (mod/main.tf)
```

There is no normal `module` call in the root's main.tf. The test run is the link.

## 4. An early provider-type resolution pass

Before `BuildConfig` returns, it calls `resolveProviderTypes` and
`resolveProviderTypesForTests` in [config.go:603](internal/configs/config.go#L603).

The root's provider map contains `docker → docker/docker`.
However, when `resolveProviderTypesForTests` processes the setup run, it selects
`run.ConfigUnderTest.resolveProviderTypes()` because this run uses the helper.
That returns an empty map: the helper declares no providers.

There is no explicit run-level provider mapping, and no helper provider name
matches the test's Docker configuration. In the final loop for unclaimed test
providers, the code assigns `NewDefaultProvider("docker")` to that configuration's
internal `providerType` field: `hashicorp/docker`.

This is an earlier assignment than the validation lookup described below.
It does not itself cause the missing-installed-provider diagnostic. The later
requirement collector independently resolves the name using the helper's module.

## 5. Prepare installed provider factories

Back in `TestCommand.Execute`, `contextOpts` calls `providerFactories`:

- [meta.go:377](internal/command/meta.go#L377)
- [meta_providers.go:220](internal/command/meta_providers.go#L220)

The lock file and local cache provide a factory for
`registry.opentofu.org/docker/docker` v0.4.1, plus built-in providers.
There is no factory for `registry.opentofu.org/hashicorp/docker`.

## 6. Select and transform the setup run

`TestSuiteRunner.Start` calls `ExecuteTestFile` for `main.tftest.hcl`.

In [test.go:379](internal/command/test.go#L379), the runner selects
`run.Config.ConfigUnderTest`. The `config` passed to `ExecuteTestRun` is therefore
the helper, not the top-level root.

`ExecuteTestRun` calls `config.TransformForTest(run.Config, file.Config, evalCtx)`.
The arguments combine two different origins:

```text
config      = helper configuration from mod/main.tf
run.Config  = setup run from main.tftest.hcl
file.Config = complete main.tftest.hcl test configuration
```

[getProviderConfigTransformForTest](internal/configs/config.go#L903) sees no
nonempty `run.Providers` mapping, so it copies every test provider into the
helper's provider configuration map.

```text
Helper BEFORE:
  ProviderConfigs = {}
  RequiredProviders = {}

Helper AFTER:
  ProviderConfigs = { docker: test's provider configuration }
  RequiredProviders = {}
```

The root's source mapping is not copied. Neither file on disk is changed.
The transformation returns a reset function to restore the original map later.

## 7. Validation turns that configuration into a requirement

The call chain is:

```text
TestFileRunner.validate                         test.go:623
  → Context.Validate                            context_validate.go:31
    → checkConfigDependencies                   context.go:326
      → config.ProviderRequirements             config.go:307
        → addProviderRequirements               config.go:387
          → loop over Module.ProviderConfigs    config.go:505
            → addProviderRequirementsFromProviderBlock  config.go:566
```

The loop finds the injected Docker configuration. Even without resources using
it, the provider block contributes a requirement.

`addProviderRequirementsFromProviderBlock` uses `provider.Name`, which is
`docker`, and calls `c.Module.ProviderForLocalConfig(...)`.
It does not use the test provider's earlier `providerType` field for this lookup.

Here `c.Module` is the helper:

```text
Module.ProviderForLocalConfig("docker")
  → Module.ImpliedProviderForUnqualifiedType("docker")
    → RequiredProviders["docker"] does not exist
    → addrs.ImpliedProviderForUnqualifiedType("docker")
      → NewDefaultProvider("docker")
        → registry.opentofu.org/hashicorp/docker
```

See [module.go:918](internal/configs/module.go#L918) and
[provider.go:82](internal/addrs/provider.go#L82).

## 8. The error and return path

`checkConfigDependencies` asks the plugin library:

```text
HasProvider(registry.opentofu.org/hashicorp/docker) → false
```

It emits `Missing required provider`. `Context.Validate` returns before graph
construction. `ExecuteTestRun` marks the run as errored and returns before
planning or applying. Its deferred reset restores the helper's provider map.

The CLI reports:

```text
main.tftest.hcl... fail
  run "setup"... fail
Error: Missing required provider
... registry.opentofu.org/hashicorp/docker ...
Failure! 0 passed, 1 failed.
```

Neither the root's Docker Hub data source nor the helper's output is applied.

## 9. Why init did not fail in the same way

When init collects requirements, it processes the test provider block using the
original root module's mapping; see [config.go:510](internal/configs/config.go#L510).
`addProviderRequirementsFromProviderBlock` resolves the name against that root,
so it requests `docker/docker`. This lookup does not use the internal providerType
assigned by the early pass either.

The helper still has no injected provider configuration during initialization.
It adds no Docker requirement. Installation therefore succeeds.

The decisive change during execution is step 6: the unused test provider is
inserted into the helper. Step 7 then resolves it in a different module context.

Removing only the provider block from main.tftest.hcl avoids that injection;
the verified control passes with `1 passed, 0 failed`.
