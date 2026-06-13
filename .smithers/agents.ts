// smithers-source: generated
import { type AgentLike, AmpAgent as SmithersAmpAgent } from "smithers-orchestrator";
import { Codex55HighAgent, Codex55LowAgent, Codex55MedAgent } from "./agents/codex";
import { OpenCodeAgent } from "./agents/opencode";
import { PiGpt55High } from "./agents/pi";

export { Codex55HighAgent, Codex55LowAgent, Codex55MedAgent } from "./agents/codex";
export { OpenCodeAgent } from "./agents/opencode";

export const providers = {
  codex: Codex55MedAgent,
  codex55High: Codex55HighAgent,
  codex55Med: Codex55MedAgent,
  codex55Low: Codex55LowAgent,
  opencode: OpenCodeAgent,
  pi: PiGpt55High,
  amp: new SmithersAmpAgent(),
} as const;

export const agents = {
  // cheapFast: Smithers would normally suggest Kimi here, but Kimi is not available: missing `kimi` on PATH; missing credentials (~/.kimi).
  // cheapFast: Smithers would normally suggest Vibe here, but Vibe is not available: missing `vibe` on PATH; missing credentials (~/.vibe/.env or ~/.vibe/config.toml or $MISTRAL_API_KEY).
  // cheapFast: Smithers would normally suggest Claude Sonnet here, but Claude Code is not available: missing `claude` on PATH.
  // cheapFast: Smithers would normally suggest Antigravity here, but Antigravity is not available: missing credentials (~/.gemini/antigravity-cli/settings.json or ~/.gemini/antigravity-cli).
  cheapFast: [providers.pi],
  smart: [providers.codex, providers.opencode, providers.amp],
  // smartTool: Smithers would normally suggest Claude Code here, but Claude Code is not available: missing `claude` on PATH.
  smartTool: [providers.codex, providers.opencode, providers.amp],
  // Dedicated Beads polish reviewer/apply pool. Add project-specific Codex agents here.
  beadsPolish: [providers.codex55High, providers.codex55Med, providers.codex55Low],
} as const satisfies Record<string, AgentLike[]>;
