/**
 * Usage Monitor — Host half.
 *
 * Discovers Codex and Grok accounts from local credential stores, reads each
 * account's remaining quota from the provider's own usage endpoint, persists a
 * non-secret snapshot, and serves it to the Web client through authenticated
 * `/api` routes. It also detects window resets/refills for reminders and
 * exposes a `usage_status` tool.
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';

import { discoverAccounts, ensureClaudeToken } from './lib/accounts.js';
import { adapters, ProviderError, providerName } from './lib/providers.js';
import { loadState, mergeCollection, saveState } from './lib/store.js';
import { asNumber, clamp, escapeAppleScript, sanitizeMessage } from './lib/util.js';

const ROUTE_PREFIX = '/api/usage-monitor';
const DEFAULT_POLL_SECONDS = 300;
const DEFAULT_REFRESH_MIN_SECONDS = 120;
const REQUEST_LIMIT_MS = 15_000;

function integer(value, fallback, min, max) {
  const parsed = asNumber(value);
  if (parsed === undefined) return fallback;
  return Math.round(clamp(parsed, min, max));
}

function normalizeConfig(raw) {
  const input = raw && typeof raw === 'object' ? raw : {};
  const notifications = input.notifications && typeof input.notifications === 'object' ? input.notifications : {};
  const discovery = input.discovery && typeof input.discovery === 'object' ? input.discovery : {};
  const ui = input.ui && typeof input.ui === 'object' ? input.ui : {};
  return {
    pollSeconds: integer(input.pollSeconds, DEFAULT_POLL_SECONDS, 60, 3600),
    refreshMinSeconds: integer(input.refreshMinSeconds, DEFAULT_REFRESH_MIN_SECONDS, 30, 3600),
    notifications: {
      toast: notifications.toast !== false,
      macos: notifications.macos === true,
      lowThreshold: integer(notifications.lowThreshold, 10, 0, 50),
    },
    discovery: {
      cli: discovery.cli !== false,
      ccSwitch: discovery.ccSwitch !== false,
    },
    claudeRefreshTokens: input.claudeRefreshTokens !== false,
    ui: { dock: !ui || ui.dock !== false },
    accounts: Array.isArray(input.accounts)
      ? input.accounts.filter((entry) => entry && typeof entry === 'object')
      : [],
  };
}

function signInHint(provider) {
  if (provider === 'codex') return 'Run `codex login` to sign in again.';
  if (provider === 'grok') return 'Run `grok login` to sign in again.';
  if (provider === 'claude') return 'Run `claude` and use /login with the subscription account.';
  return 'Sign in to this provider again.';
}

function statePath() {
  const home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
  return path.join(home, 'usage-monitor', 'state.json');
}

function json(value) {
  return Response.json(value, { headers: { 'cache-control': 'no-store' } });
}

function formatDuration(ms) {
  const totalMinutes = Math.max(0, Math.round(ms / 60_000));
  if (totalMinutes < 1) return '<1m';
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function formatWhen(iso) {
  if (!iso) return 'unknown';
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return 'unknown';
  try {
    return new Date(ms).toLocaleString('en-GB', {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return new Date(ms).toISOString();
  }
}

function toolAccount(account) {
  return {
    provider: account.provider,
    label: account.label,
    plan: account.plan || '',
    status: account.status,
    statusDetail: account.statusDetail || '',
    windows: (account.windows || []).map((window) => ({
      label: window.label,
      remainingPercent: window.remainingPercent,
      usedPercent: window.usedPercent,
      resetsAt: window.resetsAt || '',
      windowSeconds: window.windowSeconds || 0,
      exhausted: window.exhausted === true,
    })),
    extras: (account.extras || []).map((extra) => ({
      label: extra.label,
      value: extra.value || '',
      items: Array.isArray(extra.items) ? extra.items : [],
    })),
  };
}

function renderReport(value) {
  const lines = [];
  const accounts = value && Array.isArray(value.accounts) ? value.accounts : [];
  if (!accounts.length) {
    return [{ type: 'text', text: 'No Codex or Grok accounts are available. Sign in with `codex login` or `grok login`.' }];
  }
  for (const account of accounts) {
    const plan = account.plan ? ` (${account.plan})` : '';
    const status = account.status === 'ok' ? 'live' : account.status;
    lines.push(`${providerName(account.provider)} · ${account.label}${plan} — ${status}`);
    if (account.statusDetail) lines.push(`  ! ${account.statusDetail}`);
    for (const window of account.windows || []) {
      const reset = window.resetsAt
        ? ` · resets ${formatWhen(window.resetsAt)}${
            Date.parse(window.resetsAt) > Date.now() ? ` (in ${formatDuration(Date.parse(window.resetsAt) - Date.now())})` : ''
          }`
        : '';
      lines.push(
        `  ${window.label}: ${Math.round(window.usedPercent)}% used · ${Math.round(window.remainingPercent)}% left${reset}`,
      );
    }
    for (const extra of account.extras || []) {
      if (extra.value) lines.push(`  ${extra.label}: ${extra.value}`);
      if (Array.isArray(extra.items) && extra.items.length) {
        lines.push(`  ${extra.label}: ${extra.items.map((item) => `${item.label} ${Math.round(item.usedPercent)}%`).join(' · ')}`);
      }
    }
  }
  lines.push(`Generated ${formatWhen(value.generatedAt)}.`);
  return [{ type: 'text', text: lines.join('\n') }];
}

export function apply(ctx, rawConfig) {
  const config = normalizeConfig(rawConfig);
  const file = statePath();
  let state = loadState(file);
  let refreshing = null;
  const attempts = new Map();

  const sortedAccounts = () =>
    Object.values(state.accounts).sort((left, right) => {
      const rank = { codex: 0, claude: 1, grok: 2 };
      const diff = (rank[left.provider] ?? 9) - (rank[right.provider] ?? 9);
      return diff !== 0 ? diff : String(left.label).localeCompare(String(right.label));
    });

  function publicView() {
    return {
      version: 1,
      updatedAt: state.updatedAt,
      refreshing: Boolean(refreshing),
      accounts: sortedAccounts(),
      events: state.events.slice(-20),
      diag: state.diag,
      ui: {
        dock: config.ui.dock,
        toast: config.notifications.toast,
        lowThreshold: config.notifications.lowThreshold,
        pollSeconds: config.pollSeconds,
      },
    };
  }

  async function refreshOne(account) {
    const nowIso = new Date().toISOString();
    if (account.placeholder) {
      return {
        id: account.id,
        provider: account.provider,
        source: account.source,
        label: account.label,
        plan: account.plan,
        status: 'auth',
        statusDetail: 'Claude Code is not signed in',
        statusHint: 'Run `claude` and /login with the subscription account to read Claude quota.',
        windows: [],
        extras: [],
        updatedAt: nowIso,
        lastAttemptAt: nowIso,
      };
    }
    const adapter = adapters[account.provider];
    if (!adapter) return undefined;
    const signal = AbortSignal.timeout(REQUEST_LIMIT_MS);

    let current = account;
    if (account.provider === 'claude' && config.claudeRefreshTokens) {
      try {
        current = await ensureClaudeToken(account);
      } catch {
        current = account;
      }
    }

    try {
      let snapshot;
      try {
        snapshot = await adapter(current, { signal });
      } catch (error) {
        if (account.provider === 'claude' && config.claudeRefreshTokens && error && error.kind === 'auth') {
          current = await ensureClaudeToken(account, { force: true });
          snapshot = await adapter(current, { signal });
        } else {
          throw error;
        }
      }
      const nowIso = new Date().toISOString();
      return {
        id: account.id,
        provider: account.provider,
        source: account.source,
        label: snapshot.label || account.label,
        plan: snapshot.plan || account.plan,
        status: 'ok',
        windows: snapshot.windows || [],
        extras: snapshot.extras || [],
        limitReached: snapshot.limitReached === true,
        updatedAt: nowIso,
        lastSuccessAt: nowIso,
      };
    } catch (error) {
      const previous = state.accounts[account.id];
      const kind = error && typeof error.kind === 'string' ? error.kind : error instanceof ProviderError ? error.kind : 'error';
      const nowIso = new Date().toISOString();
      return {
        ...(previous || {
          id: account.id,
          provider: account.provider,
          source: account.source,
          label: account.label,
          plan: account.plan,
          windows: [],
          extras: [],
        }),
        provider: account.provider,
        source: account.source,
        status: kind === 'auth' ? 'auth' : 'error',
        statusDetail: sanitizeMessage(error),
        statusHint: kind === 'auth' ? signInHint(account.provider) : kind === 'rate-limit' ? 'The provider is rate-limiting usage checks; retrying later.' : undefined,
        updatedAt: nowIso,
        lastAttemptAt: nowIso,
      };
    }
  }

  function notifyMac(addedEvents) {
    if (!config.notifications.macos || !addedEvents.length) return;
    const pending = addedEvents
      .filter((event) => !state.notified.includes(event.id) && (event.kind === 'reset' || event.kind === 'refill'))
      .slice(-3);
    if (!pending.length) return;
    for (const event of pending) {
      const body = `${providerName(event.provider)} · ${event.label}: ${event.windowLabel} ${Math.round(event.fromUsed)}% → ${Math.round(event.toUsed)}% used`;
      const title = event.kind === 'reset' ? 'Quota reset' : 'Quota refilled';
      const script = `display notification "${escapeAppleScript(body)}" with title "Usage Monitor — ${escapeAppleScript(title)}"`;
      execFile('osascript', ['-e', script], { timeout: 5000 }, () => {});
    }
    state = { ...state, notified: [...state.notified, ...pending.map((event) => event.id)].slice(-200) };
    saveState(file, state);
  }

  async function collect({ force = false, accountId = null } = {}) {
    if (refreshing) return refreshing;
    const startedAt = Date.now();
    refreshing = (async () => {
      let accounts = [];
      let discoveryError;
      try {
        accounts = await discoverAccounts(config);
      } catch (error) {
        discoveryError = sanitizeMessage(error);
      }
      const targets = accountId ? accounts.filter((account) => account.id === accountId) : accounts;
      const results = [];
      await Promise.all(
        targets.map(async (account) => {
          const last = attempts.get(account.id) || 0;
          if (!force && startedAt - last < config.refreshMinSeconds * 1000 && state.accounts[account.id]) {
            results.push(state.accounts[account.id]);
            return;
          }
          attempts.set(account.id, startedAt);
          results.push(await refreshOne(account));
        }),
      );
      const filtered = results.filter(Boolean);
      const keepPrevious = discoveryError && Object.keys(state.accounts).length > 0 && !accountId;
      const merged = mergeCollection(state, keepPrevious ? Object.values(state.accounts) : filtered, {
        now: Date.now(),
        lowThreshold: config.notifications.lowThreshold,
        replace: !accountId,
        diag: {
          sources: config.discovery,
          accountCount: Object.keys(state.accounts).length,
          discoveryError,
          durationMs: Date.now() - startedAt,
        },
      });
      state = merged.state;
      state.diag.accountCount = Object.keys(state.accounts).length;
      saveState(file, state);
      notifyMac(merged.added);
      return publicView();
    })();
    try {
      return await refreshing;
    } finally {
      refreshing = null;
    }
  }

  function maybeRefresh() {
    const updated = state.updatedAt ? Date.parse(state.updatedAt) : 0;
    const stale = Date.now() - updated > Math.max(60, config.pollSeconds) * 1000;
    if (stale && !refreshing) {
      collect().catch(() => {});
    }
  }

  // Initial load and periodic collection.
  ctx.effect(() => {
    let stopped = false;
    const initial = setTimeout(() => {
      if (!stopped) collect().catch(() => {});
    }, 1200);
    const ticker = setInterval(() => {
      if (stopped) return;
      const updated = state.updatedAt ? Date.parse(state.updatedAt) : 0;
      if (Date.now() - updated >= config.pollSeconds * 1000) {
        collect().catch(() => {});
      }
    }, 30_000);
    return () => {
      stopped = true;
      clearTimeout(initial);
      clearInterval(ticker);
    };
  }, 'usage-monitor: scheduler');

  // On-demand provider refresh requested by the macOS menu-bar helper. The
  // helper cannot use the browser-authenticated `/api` bridge, so it drops a
  // tiny request file next to the state file instead.
  const refreshRequestFile = path.join(path.dirname(file), 'refresh.request');
  ctx.effect(() => {
    let lastRequest = 0;
    const timer = setInterval(() => {
      if (!fs.existsSync(refreshRequestFile)) return;
      try {
        fs.rmSync(refreshRequestFile, { force: true });
      } catch {
        return;
      }
      if (Date.now() - lastRequest < 8_000) return;
      lastRequest = Date.now();
      collect({ force: true }).catch(() => {});
    }, 2_000);
    return () => clearInterval(timer);
  }, 'usage-monitor: refresh requests');

  // Authenticated JSON routes for the Web client.
  const connection = ctx.get('connection');
  if (connection && connection.fetch && typeof connection.fetch.register === 'function') {
    ctx.effect(
      () =>
        connection.fetch.register({
          path: `${ROUTE_PREFIX}/state`,
          methods: ['GET'],
          requestBody: 'buffered',
          fetch: async () => {
            maybeRefresh();
            return json(publicView());
          },
        }),
      'usage-monitor: state route',
    );
    ctx.effect(
      () =>
        connection.fetch.register({
          path: `${ROUTE_PREFIX}/refresh`,
          methods: ['POST'],
          requestBody: 'buffered',
          fetch: async (request) => {
            let body = {};
            try {
              body = await request.json();
            } catch {
              body = {};
            }
            const accountId = body && typeof body.accountId === 'string' ? body.accountId : null;
            await collect({ force: true, accountId }).catch(() => {});
            return json(publicView());
          },
        }),
      'usage-monitor: refresh route',
    );
  }

  // Model-facing status tool.
  const tools = ctx.get('tools');
  if (tools && typeof tools.register === 'function') {
    ctx.effect(
      () =>
        tools.register({
          name: 'usage_status',
          description:
            'Show remaining Codex, Claude and Grok subscription quota for every local account, including each window’s percent used and reset time. Use when the user asks which account has quota left, or whether it is safe to start a long task.',
          parameters: {
            type: 'object',
            properties: {
              provider: { type: 'string', enum: ['codex', 'claude', 'grok'], description: 'Limit the report to one provider.' },
              account: { type: 'string', description: 'Case-insensitive substring of an account label or email.' },
            },
            additionalProperties: false,
          },
          output: {
            schema: {
              type: 'object',
              properties: {
                generatedAt: { type: 'string' },
                accounts: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      provider: { type: 'string' },
                      label: { type: 'string' },
                      plan: { type: 'string' },
                      status: { type: 'string' },
                      statusDetail: { type: 'string' },
                      windows: {
                        type: 'array',
                        items: {
                          type: 'object',
                          properties: {
                            label: { type: 'string' },
                            remainingPercent: { type: 'number' },
                            usedPercent: { type: 'number' },
                            resetsAt: { type: 'string' },
                            windowSeconds: { type: 'number' },
                            exhausted: { type: 'boolean' },
                          },
                          required: ['label', 'remainingPercent', 'usedPercent'],
                        },
                      },
                      extras: {
                        type: 'array',
                        items: {
                          type: 'object',
                          properties: {
                            label: { type: 'string' },
                            value: { type: 'string' },
                            items: { type: 'array', items: { type: 'object' } },
                          },
                        },
                      },
                    },
                    required: ['provider', 'label', 'status', 'windows'],
                  },
                },
              },
              required: ['generatedAt', 'accounts'],
            },
            render: (_args, value) => renderReport(value),
          },
          async execute(args) {
            const provider = args && typeof args.provider === 'string' ? args.provider : undefined;
            const needle = args && typeof args.account === 'string' ? args.account.toLowerCase() : undefined;
            const updated = state.updatedAt ? Date.parse(state.updatedAt) : 0;
            if (Date.now() - updated > Math.max(60, config.pollSeconds) * 1000) {
              await collect().catch(() => {});
            }
            const selected = sortedAccounts()
              .filter((account) => !provider || account.provider === provider)
              .filter((account) => !needle || `${account.label} ${account.id}`.toLowerCase().includes(needle))
              .map(toolAccount);
            return { generatedAt: new Date().toISOString(), accounts: selected };
          },
        }),
      'usage-monitor: usage_status tool',
    );
  }

  return {
    refresh: () => collect({ force: true }),
    snapshot: () => publicView(),
  };
}
