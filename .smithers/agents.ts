// smithers-source: generated
import { type AgentLike } from "smithers-orchestrator";
import { ClaudeCodeOpusAgent, createClaudeCodeOpusAgent } from "./agents/claude-code";
import {
  Codex55HighAgent,
  Codex55LowAgent,
  Codex55MedAgent,
  createCodex55HighAgent,
  createCodex55LowAgent,
  createCodex55MedAgent,
} from "./agents/codex";
import {
  PiDeepSeekV4Pro,
  PiGlm51,
  PiGlm52,
  PiGpt55High,
  PiKimiK27Code,
  PiMiniMaxM3,
  PiQwenCoderPlus,
  PiReadOnlyTools,
  createOpenRouterPiAgent,
  createPiGpt55High,
} from "./agents/pi";

export { ClaudeCodeFableAgent, ClaudeCodeOpusAgent, createClaudeCodeOpusAgent } from "./agents/claude-code";
export {
  Codex55HighAgent,
  Codex55LowAgent,
  Codex55MedAgent,
  createCodex55HighAgent,
  createCodex55LowAgent,
  createCodex55MedAgent,
} from "./agents/codex";
export {
  PiDeepSeekV4Pro,
  PiGlm51,
  PiGlm52,
  PiGpt55High,
  PiKimiK27Code,
  PiMiniMaxM3,
  PiQwenCoderPlus,
  PiReadOnlyTools,
  createOpenRouterPiAgent,
  createPiGpt55High,
} from "./agents/pi";

export const providers = {
  codex: Codex55HighAgent,
  claudeOpus: ClaudeCodeOpusAgent,
  codex55High: Codex55HighAgent,
  codex55Med: Codex55MedAgent,
  codex55Low: Codex55LowAgent,
  pi: PiGpt55High,
  minimaxM3: PiMiniMaxM3,
  kimiK27Code: PiKimiK27Code,
  glm51: PiGlm51,
  glm52: PiGlm52,
  qwenCoderPlus: PiQwenCoderPlus,
  deepSeekV4Pro: PiDeepSeekV4Pro,
} as const;

export const agents = {
  // cheapFast: Smithers would normally suggest Kimi here, but Kimi is not available: missing `kimi` on PATH; missing credentials (~/.kimi).
  // cheapFast: Smithers would normally suggest Vibe here, but Vibe is not available: missing `vibe` on PATH; missing credentials (~/.vibe/.env or ~/.vibe/config.toml or $MISTRAL_API_KEY).
  // cheapFast: Smithers would normally suggest Antigravity here, but Antigravity is not available: missing credentials (~/.gemini/antigravity-cli/settings.json or ~/.gemini/antigravity-cli).
  cheapFast: [providers.pi],
  cheapExecution: [providers.glm52],
  smart: [providers.codex, providers.claudeOpus],
  smartTool: [providers.codex, providers.claudeOpus],
  openRouterCode: [
    providers.minimaxM3,
    providers.kimiK27Code,
    providers.glm51,
    providers.glm52,
    providers.qwenCoderPlus,
    providers.deepSeekV4Pro,
  ],
  // Dedicated Beads polish reviewer/apply pool. Add project-specific Codex agents here.
  beadsPolish: [providers.codex55High, providers.codex55Med, providers.codex55Low],
} as const satisfies Record<string, AgentLike[]>;

export function createReadOnlySmithersAgents(env: Record<string, string>) {
  const readOnly = true;
  const piReadOnlyTools = [...PiReadOnlyTools];
  return {
    codex55High: createCodex55HighAgent(env, readOnly),
    codex55Med: createCodex55MedAgent(env, readOnly),
    codex55Low: createCodex55LowAgent(env, readOnly),
    claudeOpus: createClaudeCodeOpusAgent(env, readOnly),
    pi: createPiGpt55High(env, piReadOnlyTools),
    minimaxM3: createOpenRouterPiAgent("minimax/minimax-m3", env, "high", piReadOnlyTools),
    kimiK27Code: createOpenRouterPiAgent("moonshotai/kimi-k2.7-code", env, "high", piReadOnlyTools),
    glm51: createOpenRouterPiAgent("z-ai/glm-5.1", env, "high", piReadOnlyTools),
    glm52: createOpenRouterPiAgent("z-ai/glm-5.2", env, "high", piReadOnlyTools),
    qwenCoderPlus: createOpenRouterPiAgent("qwen/qwen3-coder-plus", env, undefined, piReadOnlyTools),
    deepSeekV4Pro: createOpenRouterPiAgent("deepseek/deepseek-v4-pro", env, "high", piReadOnlyTools),
  } as const;
}
