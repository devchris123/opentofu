# Issue #2603: proposed test cases

Local AI-assisted design notes, not an upstream contribution or implemented tests.
Companion: [concrete code trace](issue-2603-concrete-trace.md).

## 1. Proposed behavior

These are the rules discussed, not a claim about current behavior:

1. Preserve the selected configuration's explicit required_providers entries;
   they take precedence over requirements from the enclosing root module.
2. Copy root requirements only for provider configurations present in the
   selected configuration after the provider transformation.
3. When the selected configuration has no explicit requirement for such a
   provider, use the corresponding root requirement if one exists.
4. When neither declares a requirement, retain the existing default-address
   fallback.

Here, “root” means the original module containing the test file. “Helper” means
an alternate module selected by a run block. During execution the helper is
itself a root Config; it has no Parent link back to the original root.

Test-file provider blocks supply configurations. Run-level providers mappings
select and potentially rename those configurations. Neither is a
required_providers declaration.

## 2. Compatibility change to make explicit

Previously, a helper with no explicit source mapping could resolve a local name
through the hashicorp/<name> fallback. Under the proposed behavior, a root
requirement can supply a different address for that name.

That can change the provider selected for a previously successful run, if the
old inferred provider was available. This is a deliberate compatibility change
to assess, not something the tests should conceal.

The scope depends on whether rule 2 includes pre-existing helper configurations
or only configurations injected from the test file; see section 5.

## 3. Core test cases

Provider addresses below are illustrative identities; unit tests need not
install real providers. Use the real docker/docker fixture for the end-to-end
reproduction.

| ID | Setup | Expected result under the proposal |
|---|---|---|
| C1: preserve helper requirements | Helper explicitly requires a provider; root has no corresponding requirement. | Helper requirement remains unchanged, including its source and version constraint. |
| C2: helper precedence | Both declare the same local name, with different source addresses. | Do not overwrite the helper's explicit requirement. Whether passing a conflicting test configuration should also emit a diagnostic is a separate decision (D3). |
| C3: missing helper requirement | Root declares docker → docker/docker; the test supplies a Docker configuration; helper has no requirement for docker. | The transformed helper acquires the docker → docker/docker mapping. |
| C4: unused test configuration | Same as C3, but helper contains only a constant output and does not use Docker. | Validation no longer invents hashicorp/docker; the output-only test succeeds. This is issue #2603. |
| C5: unrelated root requirement | Root declares docker and random; only a Docker configuration is present after transformation. | Copy the eligible Docker requirement, not the unrelated random requirement. |
| C6: no provider configurations | Root has requirements; transformed helper has no provider configurations. | No root requirements are copied merely because they exist. Existing helper requirements remain intact. |
| C7: no source mapping anywhere | A test provider is injected, but neither root nor helper declares its requirement. | Keep the default-address fallback; success still depends on provider availability and valid configuration. |
| C8: compatibility boundary | Root declares foo → vendor/foo; helper has no foo requirement and previously resolved foo as hashicorp/foo. An eligible foo configuration is present. | Under the proposal the helper resolves foo as vendor/foo. Explicitly document that this changes the previous identity. |
| C9: ordinary root run | Run has no module block, so it tests the original root. | Existing requirements and provider configuration behavior remain unchanged; do not introduce aliasing or unnecessary mutations when source and destination are the same module. |

C4 must test dependency collection/validation as well as transformation. The
existing TestTransformForTest table only checks provider configurations and
reset behavior, so it cannot alone expose the original address mismatch.

## 4. Provider selection, aliases, and renaming

| ID | Setup | Expected result |
|---|---|---|
| M1: explicit same-name mapping | Run explicitly passes docker = docker; helper lacks a docker requirement; root has one. | Apply the same source propagation rule to the explicit mapping path. |
| M2: renamed provider | Run passes foo = docker.testing; root's docker requirement identifies vendor/docker; helper lacks foo. | Look up the source requirement using docker, and adapt it to the helper's local name foo. Do not look for a root requirement named foo merely because that is the destination name. |
| M3: renamed provider with helper requirement | Same mapping as M2, but helper explicitly declares foo. | Preserve the helper's requirement; evaluate identity conflict handling separately (D3). |
| M4: alias | Test provides docker.testing; the helper receives a Docker configuration. | Resolve the requirement by provider local name docker, not by configuration key docker.testing. |
| M5: multiple aliases | Several Docker configurations/aliases are selected. | They refer to one provider requirement per local name, not separate requirements per alias. |
| M6: explicit subset | Test file has Docker and another provider; run selects only Docker. | Do not copy the unselected test provider's requirement merely because it exists in the test file/root. Preserve independently existing helper requirements. |
| M7: implicit selection | No run-level providers mapping is given. | Preserve the existing automatic provider-configuration selection behavior, while supplying the eligible missing source mappings. |
| M8: invalid mapping | Run references a test provider configuration that does not exist. | Keep the existing missing-provider-definition diagnostic; requirements propagation must not make the invalid reference appear valid. |

An empty providers = {} currently has length zero and follows the implicit
selection branch. It must not accidentally become “select no providers” as a
side effect of this change.

## 5. Decisions still open

### D1. All resulting configurations, or only injected configurations?

Rule 2 currently says all provider configurations present after transformation.
That includes a helper's pre-existing provider blocks, even if the test file did
not supply or override them.

Distinguishing test:

- Helper has a provider configuration named foo but no explicit requirement.
- Root declares foo → vendor/foo.
- Test does not inject or override foo.

Broad rule: add vendor/foo to the helper's requirements.
Narrow rule: leave the helper's existing inferred identity unchanged.

Choose the intended behavior before fixing this expectation in a test.

### D2. Copy source identity only, or version constraints too?

The version constraint in required_providers is not deprecated. The deprecated
version attribute is the one directly inside a provider configuration block;
current code still accepts that attribute with a warning.

Cases to cover once the propagation policy is chosen:

- Root specifies a source and version constraint; helper has no requirement.
- Both modules declare the same source with compatible version constraints.
- The modules impose incompatible constraints on the same full provider address.

Preserve explicit helper requirements under rule 1. Initialization must still
account for requirements from the complete configuration/test setup, and test
execution must be consistent with the lock-file selection. Helper precedence
must not be interpreted as bypassing incompatible root constraints during init.

### D3. Identity conflicts versus precedence

Preserving the helper's requirement does not alone establish whether the
provider configuration passed to it is compatible.

Example: root maps docker to docker/docker, helper maps docker to
kreuzwerker/docker, and the run passes a test Docker configuration.

Do we diagnose incompatible resolved identities, and at which existing
validation step? Do not silently overwrite the helper's declaration to avoid
this question. Check both implicit selection and explicit run mappings.

### D4. Mock providers

The transformation also handles mock providers. Decide whether the same source
propagation policy applies to them, then cover both implicit and explicitly
mapped mocks. Do not introduce an installed-provider requirement that defeats
an otherwise valid mock-only test.

## 6. Restoration and isolation

| ID | Scenario | Expected result |
|---|---|---|
| R1 | Transform, then call reset. | Restore the helper's original provider configurations and requirements. |
| R2 | Transformation succeeds, but validation or planning fails. | Deferred reset still restores the original objects. |
| R3 | Several runs reuse a helper. | Temporary mappings from a previous run do not leak into a later run. |
| R4 | Different helpers receive providers from the same test file/root. | Updating one helper's requirements does not mutate another helper's requirements or the root's. |
| R5 | Renaming an injected requirement. | Adapting a copied requirement's local name does not mutate the original root RequiredProvider object through a shared pointer. |
| R6 | Root itself is selected. | Restoration is correct even when the source requirements and destination configuration originate from the same module. |

Check map contents and pointed-to requirement values, not only map lengths.
A shallow copy of a map can still share mutable RequiredProvider objects.

## 7. Validation layers

1. Transformation tests: configuration selection, added requirements, aliases,
   renaming, precedence, and reset/isolation.
2. Requirement-collection tests: call ProviderRequirements on the transformed
   configuration and check the full addresses. Checking providerType alone is
   insufficient because collection currently re-resolves names independently.
3. CLI reproduction: init succeeds, then test succeeds for the original
   docker/docker output-only helper fixture. Keep the passing control case.
4. Error preservation: a genuinely required unavailable provider and an invalid
   explicit provider mapping must still produce appropriate diagnostics.

The early resolveProviderTypesForTests pass must remain consistent with the
later transformed requirement lookup. A late propagation change that fixes
collection but leaves conflicting earlier type validation is incomplete.
