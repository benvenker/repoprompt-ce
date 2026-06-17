---
date: 2026-06-16
topic: upstream-sync-headless-survey
focus: Compare this fork against upstream repoprompt/repoprompt-ce and identify gaps/opportunities, especially backend harness improvements useful for rpce-headless.
mode: repo-grounded
---

# Ideation: Upstream Sync Headless Survey

## Grounding Context

This survey compared local HEAD `1a0bc62` on `codex/fable-headless-linux` with upstream `repoprompt/repoprompt-ce` main at `c8633ac`. The merge-base is `1db9bbc`. Upstream is 194 commits ahead of this working HEAD, while this branch has 38 commits not in upstream.

The central finding is simple: upstream does not have our standalone `rpce-headless` product. A naive merge would treat `Sources/RepoPromptHeadlessServer`, `Sources/RepoPromptContextCore`, Linux packaging, Fable plans, and headless smokes as deletions. Upstream's reusable value is mostly substrate: MCP lifecycle hardening, search freshness, Context Builder reliability, Git cancellation, and some test/conductor patterns.

Local headless has real architecture now: `Package.swift` defines `rpce-headless`; `Sources/RepoPromptHeadlessServer` provides stdio/full-tool MCP, restricted sockets, `oracle_send`, `context_builder`, `agent_run`, and `agent_manage`; `Sources/RepoPromptContextCore` carries shared workspace context; `Sources/RepoPromptHeadlessServer/Scripts` and `Makefile` define black-box smokes; `docs/plans/fable` captures the headless build-out.

Upstream's strongest clusters since the merge-base are:

- MCP lifecycle, concurrency, transport, diagnostics: commits `4aa23d3`, `a48fec6`, `f0f0880`, `355d6a1`, `4eb99fe`, `7b7e857`.
- Search, indexing, file freshness: commits `b326156`, `1b389a4`, `f86d4ae`, `ea845a9`, `9dae889`, `08272e7`, `1bfdaca`, `a99dec3`.
- Context Builder and worktree-aware exports: commits `38139c0`, `15ca65c`, `1a08b84`, `9073432`, `8cb7608`, `c2dcc56`.
- Git/VCS process admission and cancellation: commits `81565ae`, `8fa0fee`, `876d819`, `3a414c0`, `ee56628`.
- App/Agent Mode UI, provider model churn, release/cask packaging: active upstream areas, but lower headless leverage.

External/public signals as of 2026-06-16: upstream latest public release is `RepoPrompt CE 1.0.17`, released 2026-06-14. Main has already moved beyond that release with PRs including `#225`, `#224`, and `#226`. The public Homebrew/Sparkle lane is separate from source main and should be treated as a packaging/release signal, not as the backend sync source of truth.

Repo-local learnings matter here. Fable docs explicitly accept private-fork divergence while keeping the macOS app green. They also warn not to wholesale port app MCP/provider machinery into headless: `rpce-headless` should use narrow handlers over `RepoPromptContextCore`, and app providers are semantic references more than copy-paste sources.

## Topic Axes

- Sync topology and preservation
- Headless MCP lifecycle
- Workspace context and search freshness
- Context Builder and worktree routing
- Git/process reliability
- Upstream monitoring and release intelligence

## Ranked Ideas

### 1. Patch-stack upstream sync lane with protected headless overlays

**Description:** Treat upstream main as a source of selected patches, not as a branch we merge wholesale. Create a repeatable sync lane that first inventories upstream clusters, marks protected downstream overlays, and ports only candidate commits that survive a headless relevance check.

**Axis:** Sync topology and preservation

**Basis:** direct: `AGENTS.md` defines `rpce-headless` as a first-class agent-facing surface and identifies `.agents`, `.smithers`, `.claude`, `.codex`, `.beads`, and Fable docs as repo assets. Git comparison shows upstream `c8633ac` would delete `Sources/RepoPromptHeadlessServer` and `Sources/RepoPromptContextCore`.

**Rationale:** This prevents the sync from becoming a giant conflict marathon that accidentally erases the thing we care about. It also creates a language for future work: port, adapt, skip, or preserve.

**Downsides:** Requires discipline and probably a small tracking artifact per sync. It does not give the psychological satisfaction of being "caught up" with upstream.

**Confidence:** 92%

**Complexity:** Medium

### 2. Headless MCP lifecycle hardening bundle

**Description:** Port upstream's MCP lifecycle hardening as a small bundle for the headless server: crash-safe stderr writes, terminal cleanup records, ordered response delivery ideas, timeout policy alignment, and bounded/admission-aware tool execution. The first files to inspect are upstream `BestEffortStderrWriter.swift`, `MCPTerminalRecord.swift`, `OrderedMCPTransport.swift`, `JSONRPCBridgeLedger.swift`, and `MCPToolResourceAdmissionController.swift`.

**Axis:** Headless MCP lifecycle

**Basis:** direct: upstream commits `f0f0880`, `a48fec6`, `355d6a1`, `4eb99fe`, and `7b7e857` target closed-pipe diagnostics, response timeout recovery, long-running MCP client timeouts, shared-resource admission, and terminal cleanup. Local files affected include `Sources/RepoPromptHeadlessServer/HeadlessMCPServer.swift`, `UnixSocketListener.swift`, `HeadlessContextBuilderService.swift`, `HeadlessAgentSessionManager.swift`, and `Sources/RepoPromptShared/MCP/MCPTimeoutPolicy.swift`.

**Rationale:** Headless is process-heavy and socket-heavy. Upstream has been debugging exactly the class of failures that will make headless feel flaky under real CLI agents: disconnects, pending responses, stalled waits, and cleanup after termination.

**Downsides:** App MCP code is coupled to `MCPConnectionManager` and app view models. This should be a conceptual port with focused tests, not copied wholesale.

**Confidence:** 88%

**Complexity:** Medium

### 3. RepoPromptContextCore search freshness micro-port

**Description:** Adapt upstream `f86d4ae` and `ea845a9` into `RepoPromptContextCore`: add a core-level content-search freshness policy and invalidate retained decoded search content after overflow/recovery uncertainty. Keep this smaller than the full catalog-shard migration.

**Axis:** Workspace context and search freshness

**Basis:** direct: the search scout found local `StoreBackedWorkspaceSearch` still always uses strict disk metadata validation after `awaitAppliedIngress`, while upstream avoids redundant validation when watcher ingress proves cached content fresh and falls back to strict validation when watermarks are uncertain.

**Rationale:** Headless discovery quality lives or dies on fast, fresh file search. This is the smallest upstream search port with a clear payoff and focused tests to translate before tackling larger indexing architecture.

**Downsides:** Freshness bugs can be subtle. The port needs tests for watcher-qualified warm search, overflow invalidation, and Linux-friendly behavior.

**Confidence:** 86%

**Complexity:** Medium

### 4. Context Builder worktree/progress reliability port

**Description:** Adapt the upstream Context Builder reliability work around worktree inheritance, progress/finalization monitoring, startup/teardown races, and result-path routing into headless `context_builder`. Prioritize concepts from `ContextBuilderWorkspaceContext.swift`, `ContextBuilderFollowUpFinalizationMonitor.swift`, and `MCPContextBuilderProgressTimeline.swift`.

**Axis:** Context Builder and worktree routing

**Basis:** direct: upstream commits `38139c0`, `15ca65c`, `1a08b84`, `9073432`, `8cb7608`, and `c2dcc56` repeatedly touch Context Builder MCP handoff, startup stalls, retry lifecycle, worktree inheritance, model restoration, and teardown races. Local `HeadlessContextBuilderService.swift` is already stateful and process-heavy.

**Rationale:** Headless `context_builder` is the bridge from deterministic repository context to agent-assisted discovery. If it leaks stale results, loses worktree context, or reports poor diagnostics, it undermines the entire headless story.

**Downsides:** Upstream implementation is app-integrated. A direct copy would likely import UI lifecycle assumptions into the server. The safe route is test translation first, then local service changes.

**Confidence:** 82%

**Complexity:** Medium

### 5. Git subprocess admission and cancellation hardening

**Description:** Bring over the idea of bounded Git read workloads, subprocess admission, porcelain-v2 parsing, and pipe-drain/cancellation fixes. Start with upstream commits `81565ae`, `8fa0fee`, `876d819`, `3a414c0`, and `ee56628`.

**Axis:** Git/process reliability

**Basis:** direct: upstream added `GitProcessAdmissionController`, improved `GitService`, fixed pipe-drain descriptor races, and added cancellation tests. Headless will run in agent-heavy workspaces where Git and file search can compete with MCP requests.

**Rationale:** This is less glamorous than tool schemas, but it protects the server from becoming unresponsive under concurrent discovery, worktree, and diff-heavy agent workflows.

**Downsides:** Git behavior is cross-platform sensitive. Linux/Docker validation should be part of the first port, not a follow-up.

**Confidence:** 78%

**Complexity:** Medium

### 6. Sync preservation guardrails for local agent assets

**Description:** Add an explicit future-sync checklist or guardrail that marks local-only assets as protected: `Sources/RepoPromptHeadlessServer`, `Sources/RepoPromptContextCore`, `docs/plans/fable`, `.smithers`, `.agents`, `.claude`, `.codex`, `.beads`, `skills-lock.json`, `Makefile` headless targets, and `Scripts/package_headless_linux.sh`.

**Axis:** Sync topology and preservation

**Basis:** direct: `AGENTS.md` names repo-local agent assets as first-class state. The diff from current to upstream shows large deletes across exactly these areas, including managed skills, Smithers workflows, Fable plans, and headless scripts.

**Rationale:** This gives future sync work a tripwire. If a patch deletes a protected path, that is not a merge conflict to resolve casually; it is a product decision.

**Downsides:** A guardrail can become stale if the protected surface changes. It should be short and generated from known path prefixes.

**Confidence:** 84%

**Complexity:** Low

### 7. Release/watch intelligence lane

**Description:** Separate upstream-source sync from release/distribution watching. Track upstream `main` for backend fixes, but separately watch `v1.0.17+`, the update repo, and Homebrew cask for user-facing release signals.

**Axis:** Upstream monitoring and release intelligence

**Basis:** external: public upstream release `RepoPrompt CE 1.0.17` shipped on 2026-06-14, while upstream main already has post-release commits including `#225`, `#224`, and `#226`. The Homebrew cask consumes promoted assets from the update channel rather than source builds.

**Rationale:** This keeps backend sync from being distracted by packaging churn, while still telling us when upstream ships a release worth benchmarking or diffing for user-facing behavior.

**Downsides:** This is an intelligence/process improvement, not a backend harness improvement. It should not outrank concrete ports unless sync becomes a recurring chore.

**Confidence:** 72%

**Complexity:** Low

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Wholesale merge upstream main | Would delete or conflict with the headless product, `RepoPromptContextCore`, Linux packaging, and local agent assets. |
| 2 | Direct cherry-pick all MCP app changes | Too app-coupled; risks importing `MCPConnectionManager` and view-model assumptions into headless. |
| 3 | Port upstream Agent Mode UI polish first | Low leverage for the stated headless/backend goal. |
| 4 | Port provider/model catalog churn first | Potentially useful later, but policy-sensitive and not core to headless harness quality. |
| 5 | Full catalog-shard/per-root-index migration as first search step | Promising but too invasive for the first sync pass; start with search freshness and overflow invalidation. |
| 6 | Treat release/cask changes as the sync source of truth | Packaging lane is useful context, but backend fixes live on source main. |
| 7 | Rebase local branch directly onto upstream main | Same deletion risk as wholesale merge, plus higher conflict complexity while the worktree is already dirty. |
| 8 | Do nothing except monitor upstream | Misses several concrete reliability fixes that map well to headless failure modes. |
| 9 | Import Classic ideas | `repoprompt-classic` is archived and explicitly not the live CE upstream. |
