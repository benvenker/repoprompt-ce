import { ClaudeCodeAgent as SmithersClaudeCodeAgent } from "smithers-orchestrator";

// Built-in Claude Code CLI agent (cliEngine: "claude-code").
// Tweak `model`, `cwd`, `CLAUDE_CODE_LOCAL_PATH`, or uncomment extra options below to match your setup.
const claudeLocalPath = process.env.CLAUDE_CODE_LOCAL_PATH
  ?? (process.env.HOME ? `${process.env.HOME}/.claude/local` : undefined);
const claudePathEnv = [claudeLocalPath, process.env.PATH].filter(Boolean).join(":");

export const ClaudeCodeOpusAgent = new SmithersClaudeCodeAgent({
  model: "claude-opus-4-8",
  cwd: process.cwd(),
  env: {
    PATH: claudePathEnv,
  },
  // systemPrompt: "Add shared instructions for every Claude run.",
  // timeoutMs: 10 * 60 * 1000,
  // dangerouslySkipPermissions: true,
  extraArgs: ["--effort", "xhigh"],
});


export const ClaudeCodeFableAgent = new SmithersClaudeCodeAgent({
  model: "claude-fable-5",
  cwd: process.cwd(),
  env: {
    PATH: claudePathEnv,
  },
  extraArgs: ["--effort", "xhigh"],
});
