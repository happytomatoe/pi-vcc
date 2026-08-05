import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { loadSettings, getModelThreshold, resolveTriggerTokens } from "../core/settings";

type ProactiveContext = {
  model?: any;
  getContextUsage?: () => any;
  compact?: (options?: any) => void;
  ui?: any;
  sessionManager?: {
    getEntries?: () => any[];
    getBranch?: () => any[];
    buildContextEntries?: () => any[];
    getLeafId?: () => string;
  };
};

const formatTokens = (n: number): string => {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
};

// Cooldown after compaction to prevent double-trigger.
let lastCompactTime = 0;
const COOLDOWN_MS = 3000;

// Flag: when true, session_before_compact knows we initiated this compaction
let proactiveTriggerActive = false;

// Turn counter: skip N turns after compaction to let session build up
let turnsSkippedAfterCompact = 0;
const SKIP_TURNS_ENV = "PI_VCC_SKIP_TURNS_AFTER_COMPACT";

const setCooldown = () => { lastCompactTime = Date.now(); };
const isCoolingDown = () => Date.now() - lastCompactTime < COOLDOWN_MS;

/** Check if a proactive trigger is currently in flight. */
export const isProactiveTriggerActive = () => proactiveTriggerActive;

/** Reset all proactive state (for testing / session start). */
export const resetProactiveState = () => {
  lastCompactTime = 0;
  proactiveTriggerActive = false;
  turnsSkippedAfterCompact = 0;
};

/** Get configured number of turns to skip after compaction. */
const getSkipTurnsAfterCompact = (): number => {
  const envVal = process.env[SKIP_TURNS_ENV];
  if (envVal) {
    const parsed = parseInt(envVal, 10);
    if (!isNaN(parsed) && parsed >= 0) return parsed;
  }
  return 0;
};

/**
 * Check if a configured threshold has been crossed and trigger compaction
 * if so. Safe to call from multiple event handlers — cooldown prevents
 * double-triggering.
 */
const checkAndTrigger = (ctx: ProactiveContext, source: string) => {
  const settings = loadSettings();
  const threshold = getModelThreshold(settings, ctx.model);

  // No threshold → nothing to do (pi-core's global threshold owns it)
  if (!threshold) return;

  const contextWindow = ctx.model?.contextWindow ?? 0;
  const effectiveThreshold = resolveTriggerTokens(threshold, contextWindow);
  if (effectiveThreshold == null) return;

  const usage = ctx.getContextUsage?.();
  if (!usage || usage.tokens === null) return;

  // Only trigger if context EXCEEDS the threshold.
  if (usage.tokens <= effectiveThreshold) return;

  // Cooldown guard — prevent double-trigger within 3s of last compaction.
  if (isCoolingDown()) return;

  // Turn skip guard — after compaction, skip N turns to let session build up
  if (turnsSkippedAfterCompact > 0) return;

  // Guard: Don't trigger if there are too few messages (buildOwnCut requires >2)
  const entries = ctx.sessionManager?.getEntries?.();
  if (entries) {
    const messageCount = entries.filter((e: any) => e.type === 'message').length;
    if (messageCount <= 2) return;
  }

  try {
    const pct = Math.round((usage.tokens / contextWindow) * 100);
    ctx?.ui?.notify?.(
      `pi-vcc: [${source}] Context at ${pct}% exceeds threshold (${formatTokens(effectiveThreshold)} tok). Compacting...`,
      "info",
    );
  } catch {}

  // Set cooldown IMMEDIATELY to prevent pi-core from also triggering
  setCooldown();

  // Mark that this compaction was triggered by us
  proactiveTriggerActive = true;

  ctx.compact?.();
};

/**
 * Registers proactive configured compaction thresholds.
 *
 * Triggers:
 *
 * 1. `agent_end` — after each agent run completes, check if context
 *    exceeds the active configured threshold.
 *
 * 2. `model_select` — when switching models, the new model may have a
 *    different threshold. Check immediately.
 *
 * 3. `session_compact` — cooldown tracking + clear proactiveTriggerActive.
 *
 * 4. `agent_end` — decrement turn skip counter after compaction.
 */
export const registerProactiveThresholdHook = (pi: ExtensionAPI) => {
  pi.on("agent_end", (_event, ctx) => {
    checkAndTrigger(ctx, "auto");
  });

  pi.on("model_select", (_event, ctx) => {
    checkAndTrigger(ctx, "model-switch");
  });

  // Track compaction completion: set cooldown, set skip turns, clear self-initiated flag
  pi.on("session_compact", () => {
    setCooldown();
    proactiveTriggerActive = false;

    // Set turn skip counter after compaction
    const skipTurns = getSkipTurnsAfterCompact();
    if (skipTurns > 0) {
      turnsSkippedAfterCompact = skipTurns;
    }
  });

  // Decrement turn skip counter on each agent_end (fires after compaction)
  pi.on("agent_end", () => {
    if (turnsSkippedAfterCompact > 0) {
      turnsSkippedAfterCompact--;
    }
  });

  // Reset state on session start so state doesn't leak between sessions
  pi.on("session_start", () => {
    lastCompactTime = 0;
    proactiveTriggerActive = false;
    turnsSkippedAfterCompact = 0;
  });
};
