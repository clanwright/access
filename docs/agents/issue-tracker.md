# Issue tracker: GitHub

Tasks and specs live in GitHub Issues for `clanwright/access`.
Use the existing Keychain-backed `gh` CLI authentication.

## Operations

Read the relevant issue, including its body, labels, and comments, before
working on it. Scope tracker operations to this repository.

“Publish to the issue tracker” means create a GitHub issue.
“Fetch the relevant ticket” means read the issue and its comments.

Prepare multiline issue bodies and comments in a temporary file and pass
that file through the CLI's body-file option.

All tracker mutations follow the approval boundary in root `AGENTS.md`.
This configuration records the workflow; it grants no standing approval.

Temporary plans and draft issue bodies belong in ignored `.work/`.
GitHub Issues is the durable task tracker.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding operations

A map is one issue labelled `wayfinder:map`. Its body holds Notes,
Decisions-so-far, and Fog.

Link child tickets through GitHub sub-issues. If unavailable, use a task
list in the map and a `Part of #<map>` reference in each child.

Child types use `wayfinder:research`, `wayfinder:prototype`,
`wayfinder:grilling`, or `wayfinder:task`.

Record blockers using native issue dependencies. If unavailable, put
`Blocked by: #<number>` references at the top of the child body.

The frontier is the first open, unassigned child in map order with no
open blockers. Claim it by assigning the driving developer.

Resolve a child by recording its result, closing it, and adding a brief
result and link to the map's Decisions-so-far.
