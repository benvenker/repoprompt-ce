import { CodexAgent as SmithersCodexAgent } from "smithers-orchestrator";

// Built-in Codex CLI agent (cliEngine: "codex").
// Tweak `model`, `cwd`, or uncomment extra options below to match your setup.
export const Codex55HighAgent = new SmithersCodexAgent({
  model: "gpt-5.5",
  cwd: process.cwd(),
  skipGitRepoCheck: true,
  // systemPrompt: "Add shared instructions for every Codex run.",
  // sandbox: "workspace-write",
  // fullAuto: true,
  config: {
    model_reasoning_effort: "high",
  },
});

export const Codex55MedAgent = new SmithersCodexAgent({
  model: "gpt-5.5",
  cwd: process.cwd(),
  skipGitRepoCheck: true,
  // systemPrompt: "Add shared instructions for every Codex run.",
  // sandbox: "workspace-write",
  // fullAuto: true,
  config: {
    model_reasoning_effort: "medium",
  },
});

export const Codex55LowAgent = new SmithersCodexAgent({
  model: "gpt-5.5",
  cwd: process.cwd(),
  skipGitRepoCheck: true,
  // systemPrompt: "Add shared instructions for every Codex run.",
  // sandbox: "workspace-write",
  // fullAuto: true,
  config: {
    model_reasoning_effort: "low",
  },
});