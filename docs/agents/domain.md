# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

This is a single-context repo.

Before exploring, read:

- **`CONTEXT.md`** at the repo root for project-specific domain language.
- **`docs/adr/`** for architectural decisions that touch the area you're about to work in.

If either path does not exist in a future checkout, proceed silently. The producer skill (`/grill-with-docs`) creates these lazily when terms or decisions actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept in an issue title, refactor proposal, hypothesis, test name, or implementation note, use the term as defined in `CONTEXT.md`. Do not drift to synonyms the glossary explicitly avoids.

If the concept you need is not in the glossary yet, either reconsider whether it is project language or note the gap for `/grill-with-docs`.

## Read relevant ADRs

Read ADRs in `docs/adr/` that touch the current work. If your output contradicts an existing ADR, surface it explicitly rather than silently overriding it:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because..._
