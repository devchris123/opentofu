# Local manual regression fixtures for issue #2603

These are local, AI-assisted manual tests. Do not submit them as an OpenTofu pull request; the repository's `AGENTS.md` forbids LLM-assisted contributions. Each numbered directory is an independent test configuration containing `main.tf`, `main.tftest.hcl`, and `mod/main.tf`.

The suite uses the existing cached `docker/docker` v0.4.1 provider. It does not need a Docker daemon or credentials, because the successful cases exercise provider resolution with output-only modules or OpenTofu's built-in `terraform_data` resource.

## Reuse

From the repository root, build the current checkout and run the suite:

```sh
go build -o opentofu-2603-repro/bin/tofu ./cmd/tofu
python3 opentofu-2603-repro/manual-regression/run.py
```

If the Docker provider cache is absent, initialize `opentofu-2603-repro` first. The runner uses its `bin/tofu` and `.terraform/providers` by default. Pass `--binary PATH` or `--plugin-dir PATH` to override either path. Pass case names to run a subset, for example:

```sh
python3 opentofu-2603-repro/manual-regression/run.py 04_renamed 19_preexisting_no_test_provider
```

The runner writes `init.log` and `test.log` in each selected case. It returns nonzero on any unexpected outcome. Cases 11, 17, and 18 intentionally fail with specific diagnostics. The runner expects case 19 to pass: it fails on commit `d84aa61910` and passes with the local regression fix.

## Results on commit d84aa61910

| Cases | Observed outcome |
|---|---|
| 01–05 | Implicit provider, explicit mapping, alias, renamed mapping, and matching helper requirement: pass |
| 06 | Explicit selection ignores an unselected alias with invalid configuration: pass |
| 07–08 | Two runs using the same helper, in both orders: two passes each |
| 09 | Root plan, helper run, root apply: three passes |
| 10 | Mock provider with alternate helper: pass |
| 11 | Invalid provider mapping: expected missing-provider-definition error |
| 13 | Two aliases of one provider: pass |
| 16 | Helper with an explicit conflicting source: output-only smoke test passes; it does not establish which provider was selected |
| 17 | Incompatible helper/root version constraints: expected init failure |
| 18 | No root source requirement: expected `hashicorp/docker` fallback failure |
| 19 | **Regression:** parent commit passes; fixed commit fails with `Invalid resource type` |

Cases 12, 14, and 15 are retained as exploratory controls. Case 14 has a duplicate-provider warning caused by its root configuration, so case 19 is the clean comparison.

## Case 19: provider already present in the helper

The root declares local name `terraform` with source `docker/docker`. The test file has no provider block and runs `./mod`. That helper contains `provider "terraform" {}` and a `terraform_data` resource. The helper has no explicit requirement for `terraform`, so its provider is the built-in `terraform.io/builtin/terraform` provider.

Both commits initialize successfully. On the parent commit, `tofu test` passes. On `d84aa61910`, it fails because `terraform_data` is resolved against `registry.opentofu.org/docker/docker`, which does not support that resource. The added `getProviderRequirementsTransformForTest` scans every provider config in the helper, including ones the test never selected or copied, and imports a same-name requirement from the root.

With the local regression fix, case 19 passes again. The curated runner also passes all other cases, including the expected diagnostic checks, and the original issue reproduction still passes.
