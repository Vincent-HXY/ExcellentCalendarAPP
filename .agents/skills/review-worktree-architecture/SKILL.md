---
name: review-worktree-architecture
description: Review staged, unstaged, and untracked Git changes against README and architecture rules. Detect cross-language or cross-layer scope violations, mixed responsibilities, incomplete implementation, and independently derive and run contract or black-box tests. Use for pre-commit, dirty-worktree, architecture, scope-creep, or 未提交代码审查; do not implement fixes.
---

# Worktree Architecture Review

Review the current uncommitted development increment as a skeptical, evidence-driven reviewer. The primary subject is the final working-tree state relative to the selected baseline, not only the staged snapshot.

## Non-negotiable rules

1. **Default scope:** all staged, unstaged, renamed, deleted, conflicted, and untracked files relative to `HEAD`. A user-specified baseline or path scope overrides the default.
2. **Read-only production review:** do not stage, commit, reset, restore, checkout, clean, stash, rebase, rewrite, or fix production code during the review.
3. **Preserve user work:** never overwrite or delete a pre-existing tracked or untracked file. Temporary test artifacts must be uniquely named, tracked by the reviewer, and removed only if the reviewer created them.
4. **Evidence over intuition:** every finding must identify the changed location, the governing rule or contract, the concrete impact, and confidence. Do not invent architecture rules.
5. **Cross-layer is not automatically wrong:** a Kotlin change touching C++, or a data-layer change touching implementation code, is a review trigger—not proof of a violation. Establish necessity, ownership, dependency direction, and contract evidence first.
6. **Separate facts from inference:** put ambiguous documentation, inferred intent, missing context, and unverified risks in the final `Uncertainties and assumptions` section.
7. **Independent tests:** derive test oracles from requirements, architecture documents, public interfaces, protocols, and observable behavior—not from implementation branches, private helpers, or copied constants.
8. **No blocking clarification by default:** make the best evidence-based interpretation available and record uncertainty at the end.
9. **Findings before commentary:** report actionable findings first, ordered by severity. Avoid generic praise and style-only nits.

## Workflow

Follow the steps in order. Do not begin by editing code.

### 1. Establish the exact review boundary

Resolve the repository root and this skill's directory. Run the read-only scope collector:

```bash
python3 "<skill-directory>/scripts/collect_review_scope.py" --repo . --format json
```

If the script cannot run, use these fallbacks:

```bash
git status --porcelain=v1 -z --untracked-files=all
git diff --cached --name-status --find-renames HEAD --
git diff --name-status --find-renames --
git ls-files --others --exclude-standard -z
git diff --check HEAD --
```

Then:

- Treat `git diff HEAD` as the combined final state for tracked files.
- Inspect staged and unstaged splits whenever a path has both index and worktree changes, when the two sides cancel in the combined diff, or when they reveal an inconsistent intermediate state. Review the final working-tree content unless the user asks for a staged-only review.
- Distinguish **tested worktree state** from **would-be commit state**. If the index differs from the worktree, explicitly report that normal test execution covered the worktree and may not validate exactly what `git commit` would record.
- Include relevant untracked files in scope. Before freezing the independent test oracle, read only untracked requirements, public contracts, and test-harness files; defer untracked implementation bodies to the implementation-review pass.
- Include deletions, renames, submodule pointer changes, generated files, build files, configuration, migrations, and tests.
- If there is no valid `HEAD`, use the empty tree as the baseline and state that this is an initial-repository review.
- If no uncommitted changes exist, report that fact and stop unless another baseline was explicitly requested.
- Record the initial status manifest before creating any test artifact.

Build an internal change inventory:

```text
path | git state | language | module/layer | expected responsibility | likely reason for change
```

Do not infer module ownership from file extensions alone.

### 2. Build a governing-rule ledger

Read only the documents needed to govern the changed paths:

- applicable `AGENTS.md` files;
- architecture/design documents linked from those READMEs;
- applicable ADRs, interface specifications, schemas, and module boundary documents;
- build manifests and public interfaces when they encode dependency or ownership boundaries.

For each relevant rule, record internally:

```text
rule id | source path:line | rule text/paraphrase | applies to | strength | confidence
```

Classify rule strength:

- **Mandatory:** explicit MUST/shall/forbidden, declared dependency direction, ownership rule, or unambiguous architecture requirement.
- **Recommended:** SHOULD/preferred guidance with a stated rationale.
- **Descriptive:** explains the current design but does not clearly prohibit alternatives.
- **Ambiguous/conflicting:** multiple plausible readings or documents disagree.

Use explicit document precedence when the repository defines it. Otherwise, a more specific document may refine a general one but must not silently contradict it. Treat unresolved documentation conflicts as uncertainty, not as a proven code violation. Existing code patterns are weak evidence and do not override written architecture by themselves.

### 3. Freeze an independent test oracle before implementation review

Before reading changed implementation bodies, derive expected behavior from:

- the user's request or issue acceptance criteria;
- the governing-rule ledger;
- public headers, interfaces, API schemas, protocol definitions, and documented CLI/UI behavior;
- test-runner configuration and minimal harness conventions.

Do not use existing implementation assertions as the oracle. Existing tests may be read for harness setup, fixtures, and naming conventions, but not to copy expected behavior blindly.

Create a contract test matrix:

```text
contract/rule | observable behavior or static property | positive case | boundary/negative case | oracle source
```

When subagents are available, use a fresh test-design subagent and provide only requirements, architecture rules, public contracts, changed-file names, and test harness information. Do not provide implementation bodies, suspected bugs, intended fixes, or reviewer conclusions. If implementation details are already in the current context and no fresh subagent is available, state that test independence is weakened and freeze the written oracle before continuing.

Tests may include:

- black-box behavior and public API contract tests;
- compile/link/ABI compatibility tests;
- serialization round-trip, default, migration, and backward-compatibility tests;
- static architecture tests for forbidden imports/includes/dependencies;
- lifecycle, ownership, cancellation, error, concurrency, and boundary-value tests;
- cross-language bridge tests when public behavior spans runtimes.

### 4. Review the complete implementation delta

Read each relevant diff hunk, plus the full contents of relevant untracked implementation files, with enough surrounding code to understand control flow, ownership, data flow, and lifecycle. Do not review isolated lines without context.

Perform the following passes.

#### A. Architecture compliance

For each mandatory or recommended rule that applies:

- compare the expected module/layer responsibility with the actual changed behavior;
- verify dependency direction, public/private boundary use, data ownership, lifecycle ownership, and allowed communication paths;
- check whether new abstractions are placed in the layer that owns the policy rather than the layer that merely executes it;
- verify generated artifacts come from the declared source of truth rather than hand edits;
- distinguish a stale README from a code violation; if the source of truth is unclear, record uncertainty.

A valid architecture finding must state:

```text
expected rule -> observed change -> why they conflict -> practical consequence
```

#### B. Scope and boundary crossing

Infer the development intent in this order:

1. explicit user task or issue;
2. acceptance criteria or plan document;
3. changed tests and documentation;
4. dominant changed module and public contract;
5. file concentration and naming as weak evidence.

Label inferred intent explicitly.

Classify every material changed file internally as:

- **Required:** directly implements the stated contract.
- **Supporting:** necessary test, documentation, build, migration, adapter, or compatibility work.
- **Suspicious:** relation to the task is weak, broad, or undocumented.
- **Violating:** contradicts a governing boundary or introduces a forbidden dependency.

Look especially for:

- a task centered in one language/module unexpectedly changing another without a contract-level reason;
- lower-level or data/schema modules depending on UI, concrete storage, transport, platform, or business-policy implementations;
- use of another module's private internals instead of its public adapter/interface;
- public API, dependency, build-system, or configuration changes with no requirement or consumer;
- unrelated cleanup or refactoring mixed into the feature increment;
- a necessary cross-layer ripple that lacks matching adapters, compatibility handling, or tests.

When changes span languages, FFI, IPC, schema, or multiple architectural layers, read `references/cross-layer-checks.md` and apply only the relevant sections.

#### C. Responsibility and cohesion

Report responsibility mixing only when it creates a concrete maintenance, testability, coupling, or architecture problem. Size alone is not a finding.

Check whether a changed function, class, file, or module combines responsibilities such as:

- policy decisions and low-level execution;
- data modeling and concrete persistence/network/UI behavior;
- parsing, validation, orchestration, side effects, and presentation in one unit;
- abstraction definition and platform-specific implementation;
- state ownership and unrelated lifecycle management;
- multiple feature-specific branches inside a generic utility;
- duplicated validation, conversion, or error mapping across boundaries.

For each cohesion finding, identify the responsibilities that are mixed, the coupling created, and the smallest architectural separation that would restore a clear owner. Do not prescribe a large redesign when a local extraction or boundary correction is sufficient.

#### D. Completion and omission audit

Build a change-closure matrix and mark each applicable surface as `complete`, `missing`, `not applicable`, or `unknown`:

| Surface | Questions |
| --- | --- |
| Contract | Are declarations, definitions, documentation, and acceptance criteria aligned? |
| Callers/consumers | Were all call sites, adapters, registrations, and bindings updated? |
| Variants | Are platform, feature-flag, build-type, architecture, and language variants covered? |
| Control flow | Are success, failure, cancellation, retry, timeout, and fallback paths complete? |
| Resources | Are ownership, cleanup, lifecycle, thread affinity, and shutdown handled? |
| Data | Are defaults, validation, serialization, migration, compatibility, and unknown values handled? |
| Build/package | Are source lists, dependencies, generated code, manifests, and packaging updated? |
| API/ABI/FFI | Are signatures, types, nullability, ownership, versioning, and both sides of the bridge consistent? |
| Tests | Are required behaviors, boundaries, regressions, and negative cases covered? |
| Operations | Are configuration, logging, metrics, permissions, rollout, and documentation updated where required? |

Search changed code for partial-work signals, but verify them in context:

- `TODO`, `FIXME`, `XXX`, temporary guards, commented-out logic;
- stubs, empty handlers, placeholder returns, ignored errors/results;
- new enum or variant values not handled exhaustively;
- changed signatures with stale callers or adapters;
- schema fields written but not read, or read without defaults/migration;
- resources acquired without release, async work without cancellation, or callbacks without lifecycle cleanup;
- tests removed or weakened without replacement;
- build registration missing for a new source, test, resource, or generated artifact.

#### E. Practical risk pass

Review changed behavior for correctness, security, concurrency, performance, resource lifetime, compatibility, and failure recovery when relevant. Avoid generic checklist findings: report only concrete risks supported by the delta.

### 5. Verify with existing and independent tests

Run the narrowest repository-defined build, lint, static analysis, and existing tests that cover the change. Expand to broader tests when the risk or architecture impact justifies it and the environment permits.

Then implement and run the frozen independent tests.

Test-safety order:

1. Prefer a temporary directory or isolated repository copy when the test runner accepts external tests.
2. Otherwise create only uniquely named review test files after confirming those paths do not exist.
3. Do not edit production files or persistent build manifests in the main worktree to register a temporary test. Use command-line test discovery, an overlay, or an isolated copy.
4. Do not install or upgrade dependencies, access the network, or change environment configuration unless the user explicitly authorizes it.
5. Remove only the exact temporary files created by this review.
6. Compare the final Git status with the recorded initial manifest. Never use `git clean` or another broad cleanup command.
7. Report any test-generated side effects that remain; do not delete an unknown file merely because it appeared during testing.

If safe execution is impossible, still write the independent test code in a temporary location or include a minimal proposed patch in the report. Mark it `not run` and explain the exact blocker. Never claim verification that did not occur.

For every command, record:

```text
command | scope | exit/result | relevant output | attribution confidence
```

A failing command is not automatically caused by the uncommitted change. Distinguish product failure, test-oracle failure, harness/build failure, missing dependency, environment limitation, and pre-existing failure. Compare with the baseline in an isolated environment when feasible; otherwise state attribution uncertainty.

Do not weaken or rewrite the frozen test expectation merely to match the implementation. If the requirement itself is ambiguous, move the case to `Uncertainties and assumptions`.

### 6. Synthesize only actionable findings

Severity:

- **P0:** critical security, data loss/corruption, irrecoverable failure, or a change that must not ship.
- **P1:** likely correctness failure, broken public contract, clear architecture-boundary violation, or materially incomplete implementation.
- **P2:** significant scope, cohesion, compatibility, testability, or maintainability risk with a concrete future cost.
- **P3:** low-risk but actionable defect. Omit cosmetic preferences and ungrounded style opinions.

Confidence:

- **High:** direct rule and code evidence, reproducible failure, or deterministic static violation.
- **Medium:** strong inference with limited missing context.
- **Low:** ambiguous evidence; normally place this in the final uncertainty section rather than as a finding.

A finding must be independently understandable and use this structure:

```markdown
### [P1][High confidence] Concise problem statement
- **Location:** `path/to/file.ext:line` (and related locations)
- **Rule/contract:** `README.md:line` or other authoritative source
- **Observed:** What the uncommitted change does
- **Impact:** Concrete failure, coupling, regression, or maintenance consequence
- **Minimal remediation:** Smallest correction that restores the contract/boundary
- **Verification:** Failing test, static check, command result, or reason it was not executable
```

Do not report the same root cause multiple times. Group related symptoms under one finding and list all affected locations.

## Required final report

Use this order:

```markdown
# Review result

**Verdict:** `CHANGES REQUIRED` | `PASS WITH RISKS` | `PASS` | `BLOCKED`

## Findings

Findings ordered P0 -> P3. If none, write: `No actionable findings found.`

## Review scope and governing rules

- Baseline and included staged/unstaged/untracked scope
- Changed-file summary
- Architecture/README/AGENTS sources actually used
- Explicit or inferred task intent

## Architecture and boundary assessment

- Relevant rule results
- Required/supporting/suspicious/violating change classification
- Cross-language or cross-layer assessment

## Completion assessment

- Applicable change-closure matrix results
- Confirmed omissions and completed surfaces

## Independent verification

- Frozen contract test matrix
- Test files or temporary artifacts created
- Exact commands and results
- Existing tests versus independently authored tests
- Cleanup/status comparison

## Residual risks

Untested paths, environment limits, large generated/binary changes, or risks not strong enough to be findings.

## Uncertainties and assumptions

List every unresolved architecture interpretation, inferred intent, unavailable dependency, ambiguous requirement, and attribution limit. If none, write `None.`
```

The `Uncertainties and assumptions` section must always be last.
