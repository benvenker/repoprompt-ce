// smithers-source: generated
import { type AgentLike } from "smithers-orchestrator";
import { ClaudeCodeOpusAgent } from "./agents/claude-code";
import { Codex55HighAgent, Codex55LowAgent, Codex55MedAgent } from "./agents/codex";
import { PiGpt55High } from "./agents/pi";

export { ClaudeCodeFableAgent, ClaudeCodeOpusAgent } from "./agents/claude-code";
export { Codex55HighAgent, Codex55LowAgent, Codex55MedAgent } from "./agents/codex";

export const providers = {
  codex: Codex55HighAgent,
  claudeOpus: ClaudeCodeOpusAgent,
  codex55High: Codex55HighAgent,
  codex55Med: Codex55MedAgent,
  codex55Low: Codex55LowAgent,
  pi: PiGpt55High,
} as const;

export const agents = {
  // cheapFast: Smithers would normally suggest Kimi here, but Kimi is not available: missing `kimi` on PATH; missing credentials (~/.kimi).
  // cheapFast: Smithers would normally suggest Vibe here, but Vibe is not available: missing `vibe` on PATH; missing credentials (~/.vibe/.env or ~/.vibe/config.toml or $MISTRAL_API_KEY).
  // cheapFast: Smithers would normally suggest Antigravity here, but Antigravity is not available: missing credentials (~/.gemini/antigravity-cli/settings.json or ~/.gemini/antigravity-cli).
  cheapFast: [providers.pi],
  smart: [providers.codex, providers.claudeOpus],
  smartTool: [providers.codex, providers.claudeOpus],
  // Dedicated Beads polish reviewer/apply pool. Add project-specific Codex agents here.
  beadsPolish: [providers.codex55High, providers.codex55Med, providers.codex55Low],
} as const satisfies Record<string, AgentLike[]>;
