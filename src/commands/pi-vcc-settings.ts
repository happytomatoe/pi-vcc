import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { dirname } from "path";
import { SETTINGS_PATH_DEFAULT } from "../core/settings";

const settingsPath = (): string =>
  process.env.PI_VCC_CONFIG_PATH ?? SETTINGS_PATH_DEFAULT;

interface Config {
  globalThreshold?: { reserveTokens?: number };
  [key: string]: unknown;
}

const readConfig = (): Config => {
  const path = settingsPath();
  try {
    if (!existsSync(path)) return {};
    return JSON.parse(readFileSync(path, "utf-8")) as Config;
  } catch {
    return {};
  }
};

const writeConfig = (config: Config): void => {
  const path = settingsPath();
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
};

const parseThresholdArg = (arg: string): number | null => {
  const trimmed = arg.trim().toUpperCase();
  // Match: "5k", "5K", "5000", "5.5k"
  const match = trimmed.match(/^(\d+(?:\.\d+)?)(K)?$/);
  if (!match) return null;
  const num = parseFloat(match[1]);
  if (!Number.isFinite(num) || num < 0) return null;
  return match[2] === "K" ? Math.round(num * 1000) : Math.round(num);
};

const formatTokens = (n: number): string => {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
};

export const registerPiVccSettingsCommand = (pi: ExtensionAPI) => {
  pi.registerCommand("pi-vcc::settings", {
    description:
      "Show or set the compaction threshold. No args shows current; a number (e.g. 5000 or 5K) sets it.",
    handler: async (args: string, ctx) => {
      const raw = args.trim();

      if (!raw) {
        // Show current threshold
        const config = readConfig();
        const current = config.globalThreshold?.reserveTokens;
        if (current != null) {
          ctx.ui.notify(
            `Current threshold: ${formatTokens(current)} tokens (${current})`,
            "info",
          );
        } else {
          ctx.ui.notify("No threshold configured (using pi-core default)", "info");
        }
        return;
      }

      // Parse the new threshold
      const tokens = parseThresholdArg(raw);
      if (tokens == null) {
        ctx.ui.notify(
          'Invalid threshold. Use a number like "5000" or "5K" (K = thousands).',
          "error",
        );
        return;
      }

      // Update config
      const config = readConfig();
      if (!config.globalThreshold) {
        config.globalThreshold = {};
      }
      config.globalThreshold.reserveTokens = tokens;
      writeConfig(config);

      ctx.ui.notify(
        `Threshold set to ${formatTokens(tokens)} tokens (${tokens})`,
        "success",
      );
    },
  });
};
