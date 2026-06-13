import { PiAgent as SmithersPiAgent } from "smithers-orchestrator";

// Planning
export const PiGpt55Pro = new SmithersPiAgent({
    provider: "openai",
    model: "gpt-5.5-pro",
    thinking: "high",
});

export const PiGpt55High = new SmithersPiAgent({
    provider: "openai",
    model: "gpt-5.5",
    thinking: "high",
});

export const PiGpt55XHigh = new SmithersPiAgent({
    provider: "openai",
    model: "gpt-5.5",
    thinking: "xhigh",
});

// Context gathering
export const PiGpt55low = new SmithersPiAgent({
    provider: "openai",
    model: "gpt-5.5",
    thinking: "low",
});