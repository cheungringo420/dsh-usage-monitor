/** Provider adapters. Read-only quota calls; no credential is ever persisted or logged. */

import { asNumber, clamp, isoFromMs, parseDateMs, round1, sanitizeMessage, windowKey, windowLabel } from './util.js';

const CODEX_USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';
const GROK_BILLING_URL = 'https://cli-chat-proxy.grok.com/v1/billing?format=credits';
const CLAUDE_USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const REQUEST_TIMEOUT_MS = 12_000;

export class ProviderError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.name = 'ProviderError';
    this.kind = kind;
    this.status = status;
  }
}

async function fetchJson(url, { headers, signal, timeoutMs = REQUEST_TIMEOUT_MS }) {
  const controller = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);
  const forwardAbort = () => controller.abort();
  if (signal) {
    if (signal.aborted) controller.abort();
    else signal.addEventListener('abort', forwardAbort, { once: true });
  }
  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: { accept: 'application/json', ...headers },
      signal: controller.signal,
    });
    const text = await response.text();
    if (response.status === 401 || response.status === 403) {
      throw new ProviderError('auth', `HTTP ${response.status}`, response.status);
    }
    if (response.status === 429) {
      throw new ProviderError('rate-limit', 'HTTP 429', response.status);
    }
    if (!response.ok) {
      throw new ProviderError('http', `HTTP ${response.status}`, response.status);
    }
    try {
      return JSON.parse(text);
    } catch {
      throw new ProviderError('parse', 'Malformed JSON response');
    }
  } catch (error) {
    if (error instanceof ProviderError) throw error;
    if (error && error.name === 'AbortError') {
      throw new ProviderError('timeout', timedOut ? 'Request timed out' : 'Request cancelled');
    }
    throw new ProviderError('network', sanitizeMessage(error));
  } finally {
    clearTimeout(timer);
    if (signal) signal.removeEventListener('abort', forwardAbort);
  }
}

function normalizeCodexWindow(raw, now, position) {
  if (!raw || typeof raw !== 'object') return undefined;
  const used = asNumber(raw.used_percent);
  if (used === undefined) return undefined;
  const seconds = asNumber(raw.limit_window_seconds);
  const resetAfter = asNumber(raw.reset_after_seconds);
  let resetMs = parseDateMs(raw.reset_at);
  if (resetMs === undefined && resetAfter !== undefined) resetMs = now + resetAfter * 1000;
  const key = windowKey(seconds, position);
  return {
    key,
    label: windowLabel(seconds, position === 'primary' ? '5-hour' : 'Weekly'),
    usedPercent: round1(clamp(used, 0, 100)),
    remainingPercent: round1(clamp(100 - used, 0, 100)),
    windowSeconds: seconds !== undefined ? Math.round(seconds) : undefined,
    resetsAt: isoFromMs(resetMs),
    exhausted: used >= 100,
  };
}

function codexExtras(data) {
  const extras = [];
  const credits = data && data.credits;
  if (credits && typeof credits === 'object') {
    if (credits.unlimited === true) {
      extras.push({ kind: 'text', label: 'Credits', value: 'Unlimited' });
    } else if (credits.balance !== null && credits.balance !== undefined) {
      extras.push({ kind: 'text', label: 'Credits', value: String(credits.balance) });
    }
    if (credits.overage_limit_reached === true) {
      extras.push({ kind: 'warning', label: 'Overage', value: 'Limit reached' });
    }
  }
  if (data && data.spend_control && data.spend_control.reached === true) {
    extras.push({ kind: 'warning', label: 'Spend control', value: 'Reached' });
  }
  return extras;
}

export async function fetchCodex(account, { signal } = {}) {
  const headers = {
    authorization: `Bearer ${account.token}`,
    'user-agent': 'codex_cli_rs/0.50.0',
  };
  if (account.accountId) headers['chatgpt-account-id'] = account.accountId;
  const data = await fetchJson(CODEX_USAGE_URL, { headers, signal });
  const rateLimit = (data && data.rate_limit) || {};
  const now = Date.now();
  const windows = [];
  const primary = normalizeCodexWindow(rateLimit.primary_window, now, 'primary');
  const secondary = normalizeCodexWindow(rateLimit.secondary_window, now, 'secondary');
  if (primary) windows.push(primary);
  if (secondary) windows.push(secondary);
  if (!windows.length) throw new ProviderError('parse', 'No rate-limit windows in response');
  return {
    identity: (data && data.account_id) || account.accountId,
    label: (data && data.email) || account.label,
    plan: (data && data.plan_type) || account.plan,
    windows,
    extras: codexExtras(data),
    limitReached: rateLimit.limit_reached === true || rateLimit.allowed === false,
  };
}

const PRODUCT_LABELS = {
  GrokBuild: 'Grok Build',
  GrokChat: 'Chat',
  Api: 'API',
  Imagine: 'Imagine',
  Voice: 'Voice',
};

function productLabel(product) {
  const raw = String(product || '').trim();
  if (PRODUCT_LABELS[raw]) return PRODUCT_LABELS[raw];
  return raw.replace(/([a-z])([A-Z])/g, '$1 $2') || 'Other';
}

export async function fetchGrok(account, { signal } = {}) {
  const data = await fetchJson(GROK_BILLING_URL, {
    headers: {
      authorization: `Bearer ${account.token}`,
      'user-agent': 'dsh-usage-monitor/1.0',
      'x-grok-client-mode': 'cli',
    },
    signal,
  });
  const config = (data && data.config) || data || {};
  const hasPeriod = Boolean(config.currentPeriod || config.billingPeriodEnd);
  const used = asNumber(config.creditUsagePercent);
  if (used === undefined && !hasPeriod) throw new ProviderError('parse', 'No credit usage in response');
  // A fresh weekly period omits creditUsagePercent until the first request.
  const usedValue = used ?? 0;
  const startMs = parseDateMs(config.currentPeriod && config.currentPeriod.start) ?? parseDateMs(config.billingPeriodStart);
  const endMs = parseDateMs(config.currentPeriod && config.currentPeriod.end) ?? parseDateMs(config.billingPeriodEnd);
  const windowSeconds = startMs !== undefined && endMs !== undefined
    ? Math.max(60, Math.round((endMs - startMs) / 1000))
    : 7 * 24 * 60 * 60;
  const extras = [];
  const products = Array.isArray(config.productUsage)
    ? config.productUsage
        .filter((entry) => entry && entry.product && asNumber(entry.usagePercent) !== undefined)
        .map((entry) => ({
          label: productLabel(entry.product),
          usedPercent: round1(clamp(entry.usagePercent, 0, 100)),
        }))
    : [];
  if (products.length) extras.push({ kind: 'products', label: 'Breakdown', items: products });
  const prepaid = asNumber(config.prepaidBalance && config.prepaidBalance.val);
  if (prepaid !== undefined && prepaid > 0) {
    extras.push({ kind: 'text', label: 'Prepaid', value: `$${prepaid.toFixed(2)}` });
  }
  const onDemandCap = asNumber(config.onDemandCap && config.onDemandCap.val);
  if (onDemandCap !== undefined && onDemandCap > 0) {
    const onDemandUsed = asNumber(config.onDemandUsed && config.onDemandUsed.val) ?? 0;
    extras.push({ kind: 'text', label: 'On-demand', value: `$${onDemandUsed.toFixed(2)} / $${onDemandCap.toFixed(2)}` });
  }
  return {
    identity: account.identity,
    label: account.email || account.label,
    plan: account.plan,
    windows: [
      {
        key: windowSeconds === 604800 ? 'week' : windowKey(windowSeconds, 'week'),
        label: windowLabel(windowSeconds, 'Weekly'),
        usedPercent: round1(clamp(usedValue, 0, 100)),
        remainingPercent: round1(clamp(100 - usedValue, 0, 100)),
        windowSeconds,
        resetsAt: isoFromMs(endMs),
        exhausted: usedValue >= 100,
      },
    ],
    extras,
    limitReached: usedValue >= 100,
  };
}

function pushClaudeWindow(windows, raw, key, label, windowSeconds) {
  if (!raw || typeof raw !== 'object') return;
  const used = asNumber(raw.utilization);
  if (used === undefined) return;
  const resetMs = parseDateMs(raw.resets_at);
  windows.push({
    key,
    label,
    usedPercent: round1(clamp(used, 0, 100)),
    remainingPercent: round1(clamp(100 - used, 0, 100)),
    windowSeconds,
    resetsAt: isoFromMs(resetMs),
    exhausted: used >= 100,
  });
}

/**
 * Claude Code `/usage` payload. Live payloads report `utilization` as a
 * 0-100 percent (not a fraction); `resets_at` may be null for the 5-hour
 * window when there has been no recent activity.
 */
export async function fetchClaude(account, { signal } = {}) {
  const data = await fetchJson(CLAUDE_USAGE_URL, {
    headers: {
      authorization: `Bearer ${account.token}`,
      'anthropic-beta': 'oauth-2025-04-20',
      'user-agent': 'claude-cli/2.0.0 (external, cli)',
    },
    signal,
  });
  const windows = [];
  pushClaudeWindow(windows, data.five_hour, '5h', '5-hour', 5 * 60 * 60);
  pushClaudeWindow(windows, data.seven_day, 'week', 'Weekly', 7 * 24 * 60 * 60);
  pushClaudeWindow(windows, data.seven_day_opus, 'opus', 'Opus weekly', 7 * 24 * 60 * 60);
  pushClaudeWindow(windows, data.seven_day_sonnet, 'sonnet', 'Sonnet weekly', 7 * 24 * 60 * 60);

  const extra = data.extra_usage;
  if (extra && typeof extra === 'object' && extra.is_enabled === true) {
    pushClaudeWindow(windows, extra, 'extra', 'Extra usage', 30 * 24 * 60 * 60);
  }
  if (!windows.length) throw new ProviderError('parse', 'No usage windows in response');

  const extras = [];
  const monthlyLimit = asNumber(extra && extra.monthly_limit);
  const usedCredits = asNumber(extra && extra.used_credits);
  if (monthlyLimit !== undefined && monthlyLimit > 0) {
    extras.push({
      kind: 'text',
      label: 'Extra usage',
      value: usedCredits !== undefined ? `${Math.round(usedCredits)} / ${Math.round(monthlyLimit)}` : String(Math.round(monthlyLimit)),
    });
  }

  return {
    identity: account.identity,
    label: account.email || account.label,
    plan: account.plan,
    windows,
    extras,
    limitReached: windows.some((window) => window.exhausted === true),
  };
}

export const adapters = {
  codex: fetchCodex,
  grok: fetchGrok,
  claude: fetchClaude,
};

export function providerName(provider) {
  if (provider === 'codex') return 'Codex';
  if (provider === 'grok') return 'Grok';
  if (provider === 'claude') return 'Claude';
  return provider;
}
