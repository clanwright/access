# Domain docs

## Authority and layout

Access uses a single-context layout:

- `CONTEXT.md`: shared domain vocabulary.
- `docs/adr/`: resolved architectural decisions.

Follow the authority order in root `AGENTS.md`. `README.md` remains the
documentation index; service READMEs own service APIs and implementation
details. Domain docs record vocabulary and decision rationale, with links
to canonical documentation instead of copied specifications.

Temporary plans and unresolved proposals belong in ignored `.work/`.

## Before exploring

Read root `CONTEXT.md` when present and ADRs relevant to the task.
Follow README links to the canonical documentation for the affected area.

If context or ADR files are absent, proceed silently. Create them through
domain-modeling when vocabulary or decisions are actually resolved;
setup does not create placeholder documents.

## Vocabulary and decisions

Use glossary terms consistently in issues, proposals, code, and tests.
When a needed concept is missing, check existing project terminology
before proposing a glossary addition.

Surface conflicts with existing ADRs explicitly, identifying the decision
and the reason to revisit it. Record an accepted replacement as a
superseding decision.
