# Codex Task Workflow

Use this process for every non-trivial task in this repository. Its purpose is
to preserve understanding, decisions, progress, and verification across long
sessions, interruptions, and context compaction without reducing Codex's normal
ability to proceed autonomously.

## 0. Classify and set up

Skip the task workspace for a one-line edit, a simple read-only answer, or a
small change whose intent and verification are obvious.

For other work, derive a short kebab-case slug and create:

```text
.codex/tasks/<slug>/
```

Create files only when their phase begins:

- `00-brief.md` — the requested outcome in Codex's own words, scope,
  constraints, assumptions, acceptance criteria, and explicitly excluded work.
- `01-research.md` — files inspected, relevant paths, existing patterns,
  external facts checked, current Git state, and important findings.
- `02-plan.md` — phased checklist with a verifiable result for each phase.
- `03-progress.md` — dated record of completed phases, edits, commands, test
  results, and remaining work.
- `04-decisions.md` — consequential choices, alternatives, rationale, open
  questions, and blockers.
- `05-validation.md` — final comparison with the brief, commands and checks run,
  results, limitations, and any manual validation still required.
- `06-test-cases.md` — Make a record of all the test cases that are implemented during the
  development, the test cases should be made in an orderly manner with test cases under a test suite.
  requirement-linked test cases covering expected behavior, failure paths, boundaries, and execution status.
- `07-user-manual.md` — make a user manual of the core doctypes which has the standard flow, 
  For the customizations that are done in a custom app the user manual has to be updated as per the changes in the doctypes, a user-facing operating guide or a draft for permanent project documentation when the task changes how users operate the product.
- `scratch.md` — temporary notes, experiments, discarded approaches, and command
  fragments that are not authoritative.

Task notes must not contain passwords, tokens, customer data, private keys, or
other secrets.

### Brief requirements

Record in `00-brief.md`:

- the user-visible problem, expected result and validation of the expected results;
- the authorized scope and files/systems likely to be affected;
- assumptions that are safe and reversible;
- acceptance examples and failure/boundary cases supplied by the user;
- whether data, compatibility, security, installation, or destructive actions
  are involved; and
- relevant pre-existing worktree changes that must be preserved.

## 1. Explore before editing

Inspect the relevant code, configuration, tests, documentation, and Git state
before implementation. Prefer `rg` and `rg --files` for repository searches.

For version-sensitive, high-stakes, niche, or explicitly requested facts, use
the appropriate available skill or authoritative source. Record the conclusion
and source in `01-research.md`; do not copy large external documents into task
notes.

During exploration:

- identify ownership boundaries and the smallest safe change surface;
- find existing conventions before introducing a new pattern;
- distinguish generated files from source files;
- identify existing user changes and avoid overwriting or reverting them;
- determine realistic verification commands; and
- do not edit implementation files until the relevant exploration is complete.

Read-only diagnostic commands are allowed. If urgent containment or a trivial
prerequisite must happen first, record why in `04-decisions.md`.

## 2. Plan proportionally

Write `02-plan.md` as short, outcome-oriented phases:

```markdown
## Phase 1: <name>

- [ ] <action with observable completion condition>
- [ ] <verification for this phase>

## Phase 2: <name>

- [ ] <action with observable completion condition>
```

Include:

- implementation steps in dependency order;
- verification after risky or independently testable phases;
- compatibility, migration, rollback, or recovery decisions when relevant;
- explicit acceptance checks for every requested behavior; and
- documentation or handoff work only when the change actually needs it.

Use Codex's plan/TODO mechanism as the concise user-visible plan when useful;
the task file is the durable detailed record.

Do not automatically stop after planning. Continue implementation when the
user asked to build, change, fix, or complete the task. Pause for approval only
when:

- the user explicitly requested a plan or review before implementation;
- a missing choice would materially change the product or architecture;
- new authorization, credentials, spending, or external coordination is
  required; or
- the next action is destructive, irreversible, or meaningfully outside the
  original scope.

## 3. Execute in verifiable phases

Work through one phase at a time while allowing closely related, independent
checks to run in parallel when safe.

For each phase:

1. Give the user a concise commentary update before tool-driven work.
2. Make the smallest coherent change; use `apply_patch` for manual file edits.
3. Preserve unrelated changes and follow repository-local instructions.
4. Run focused tests, builds, linting, or diagnostics appropriate to the phase.
5. Check completed items in `02-plan.md`.
6. Add a dated entry to `03-progress.md` containing changes, rationale, commands,
   results, surprises, and the next step.
7. Record only consequential trade-offs or changed assumptions in
   `04-decisions.md`.

Do not claim a command, environment, deployment, UI path, or manual scenario was
validated unless it was actually run or observed. Clearly distinguish automated
verification from checks the user must perform later.

If interrupted or compacted, resume by reading `00-brief.md`, the unchecked
items in `02-plan.md`, the latest `03-progress.md` entry, and open items in
`04-decisions.md`. Recheck the worktree before continuing.

## 4. Handle ambiguity and blockers

Make reasonable, reversible assumptions that stay inside the request and write
material assumptions in `00-brief.md` or `04-decisions.md`.

Ask the user only when the answer cannot be discovered safely and guessing could
cause product divergence, data loss, security exposure, external side effects,
or substantial rework. When asking, state:

- what is known;
- the exact missing decision;
- the recommended choice and its consequence; and
- what work can continue without the answer.

Before declaring a blocker, exhaust safe in-scope diagnostics and alternatives.
Record the evidence and the precise condition needed to continue.

Delegation or sub-agents are optional tools, not a workflow requirement. Use
them only when the user's request, applicable instructions, and available tools
authorize them and the work can be safely divided.

## 5. Verify against the brief

Before declaring completion:

1. Re-read `00-brief.md` and the user's latest request.
2. Inspect the final diff and confirm only intended files changed.
3. Run the strongest practical targeted tests, then the broader relevant suite
   or build when proportionate to risk.
4. Test failure, boundary, recovery, security, and data-preservation paths when
   the change touches them.
5. Confirm documentation and configuration match actual behavior.
6. Record each acceptance criterion in `05-validation.md` as `Passed`, `Partial`,
   `Pending`, or `Not applicable`, with evidence.
7. Record any unrun checks and why they were not run.

Never weaken, delete, or bypass a failing test merely to obtain a green result
unless the test is demonstrably obsolete and the reason is documented.

## 6. Write Proper Test Cases Under Test Suite

Create `06-test-cases.md` when a task adds or changes behavior. Derive every test
case from `00-brief.md`, the acceptance criteria, affected risks, and the final
implementation. Documentation-only or internal refactoring tasks may mark this
section `Not applicable` with a short reason.

Use this prompt when preparing the test cases:

```text
Create a requirement-linked test case document for this task. Read 00-brief.md,
02-plan.md, 03-progress.md, 04-decisions.md, the changed implementation, and the
existing test patterns. For each test case include: ID, requirement or risk,
test level (unit/integration/end-to-end/manual), preconditions, test data, exact
steps, expected result, automation location or manual owner, and current status.
Cover the normal path, validation errors, meaningful boundaries, failure and
recovery paths, permissions/security, compatibility, and data preservation when
relevant. Do not invent execution results. Mark each case Planned, Automated,
Passed, Failed, Blocked, or Manual-Pending and link actual evidence from
05-validation.md.
```

Keep test cases specific and observable. Do not duplicate low-value variations,
and do not mark a case `Passed` merely because its test code exists.

## 7. Write User Manual for User Ease

Create `07-user-manual.md` when the task introduces or changes a user-visible
installation, configuration, operation, recovery procedure, screen, or workflow.
Use it as a reviewed draft during the task. Move lasting instructions into the
repository's real documentation before completion; do not make the scratch task
folder the only location of the user manual.

Use this prompt when preparing the user manual:

```text
Write a user manual for the behavior delivered by this task. Base it only on the
verified implementation and 05-validation.md. Identify the intended audience,
prerequisites, supported environment, permissions, and any safety warning. Give
numbered steps for setup and normal operation, explain the visible result after
each important action, and include recovery, backup/restore, troubleshooting,
and uninstall/reset guidance only when relevant. Use the exact labels and paths
shown by the product. Add screenshot placeholders only where a visual is truly
needed. Never include secrets, developer-only commands, unsupported promises, or
steps that were not verified. Clearly label administrator actions, destructive
actions, known limitations, and manual checks.
```

Review the manual against the finished product and the supported platform. Any
unverified instruction must be labeled clearly rather than presented as tested.

## 8. Wrap up

The final response should lead with the outcome and include only what helps the
user continue:

- what changed and why;
- the most important files as clickable paths;
- tests/checks that passed or failed;
- unresolved limitations, manual checks, or follow-up work; and
- destructive or unrecoverable actions taken, if any.

Keep the task folder by default so future Codex sessions can recover the work
history. Task folders are Git-ignored and must not be referenced from product
documentation or treated as permanent design records. Promote lasting decisions
to real project documentation or an ADR.

Delete task scratch only when the user requests cleanup or the repository's
retention policy explicitly requires it. Before deletion, ensure no unique
decision or validation evidence exists only in scratch.


## Standing rules

- Preserve user intent and authorization boundaries.
- Explore and plan in proportion to task complexity and risk.
- Prefer several coherent, verifiable phases over one large unverified change.
- Keep `03-progress.md` current enough to resume after interruption.
- Use `04-decisions.md` for meaningful decisions, not routine implementation
  details.
- Never revert or overwrite unrelated user changes.
- Never use destructive Git or data commands without explicit authorization.
- Treat tests, logging, error messages, migrations, and recovery behavior as
  product behavior when users depend on them.
- Do not let task-note maintenance become more work than the task itself.
