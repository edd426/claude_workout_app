/**
 * Chat proxy guardrails (issue #90).
 *
 * The Anthropic key lives server-side and is billed to the owner; a
 * malformed or malicious client call must not be able to pick an arbitrary
 * model or an unbounded token ceiling.
 */

// Hardcoded default: the model ids the iOS app actually sends today
// (ClaudeLifter/Utilities/SettingsManager.swift AIModel cases).
export const DEFAULT_ALLOWED_MODELS = [
  "claude-haiku-4-5-20251001",
  "claude-sonnet-4-6",
  "claude-opus-4-7",
];

export function getAllowedModels(): string[] {
  const raw = process.env.ALLOWED_MODELS;
  if (!raw || raw.trim().length === 0) {
    return DEFAULT_ALLOWED_MODELS;
  }
  const parsed = raw
    .split(",")
    .map((m) => m.trim())
    .filter((m) => m.length > 0);
  return parsed.length > 0 ? parsed : DEFAULT_ALLOWED_MODELS;
}

export function isModelAllowed(model: string): boolean {
  return getAllowedModels().includes(model);
}

// The iOS app's extended-thinking path sends thinking_budget: 10000, which
// bumps max_tokens to 14096 (see ChatViewModel.swift / AnthropicService.swift:
// max(4096, thinking_budget + 4096)). Default cap must clear that with room
// to spare while still rejecting genuinely unbounded requests.
export const DEFAULT_MAX_TOKENS_CAP = 24576;

export function getMaxTokensCap(): number {
  const raw = process.env.MAX_TOKENS_CAP;
  const parsed = raw ? Number.parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_TOKENS_CAP;
}
