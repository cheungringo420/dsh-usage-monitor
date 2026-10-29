/** Durable, non-secret snapshot state: numbers, labels, sanitized failures, events. */

import fs from 'node:fs';
import path from 'node:path';

export const STATE_VERSION = 1;

export function emptyState() {
  return {
    version: STATE_VERSION,
    updatedAt: null,
    accounts: {},
    events: [],
    notified: [],
    diag: {},
  };
}

export function loadState(file) {
  try {
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!raw || raw.version !== STATE_VERSION || typeof raw.accounts !== 'object' || raw.accounts === null) {
      return emptyState();
    }
    return {
      ...emptyState(),
      ...raw,
      accounts: raw.accounts,
      events: Array.isArray(raw.events) ? raw.events : [],
      notified: Array.isArray(raw.notified) ? raw.notified : [],
      diag: raw.diag && typeof raw.diag === 'object' ? raw.diag : {},
    };
  } catch {
    return emptyState();
  }
}

export function saveState(file, state) {
  const directory = path.dirname(file);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, file);
  try {
    fs.chmodSync(file, 0o600);
  } catch {
    // best effort on filesystems without POSIX modes
  }
}

function windowEventId(accountId, window, kind) {
  return `${accountId}:${window.key}:${window.resetsAt || 'none'}:${kind}`;
}

function detectEvents(previous, next, lowThreshold, nowIso) {
  const events = [];
  if (!previous || !Array.isArray(previous.windows) || !previous.windows.length) return events;
  for (const window of next.windows || []) {
    if (typeof window.remainingPercent !== 'number' || typeof window.usedPercent !== 'number') continue;
    const before = previous.windows.find((candidate) => candidate.key === window.key);
    if (!before || typeof before.usedPercent !== 'number') continue;
    const beforeReset = before.resetsAt ? Date.parse(before.resetsAt) : undefined;
    const nextReset = window.resetsAt ? Date.parse(window.resetsAt) : undefined;
    const windowMs = (window.windowSeconds || 0) * 1000;
    const moved = beforeReset !== undefined && nextReset !== undefined ? nextReset - beforeReset : 0;
    const resetMoved = moved > Math.max(60_000, windowMs ? windowMs * 0.25 : 0);
    const dropped = before.usedPercent - window.usedPercent;

    if (resetMoved && dropped > 0.5) {
      events.push({
        id: windowEventId(next.id, window, 'reset'),
        at: nowIso,
        kind: 'reset',
        accountId: next.id,
        provider: next.provider,
        label: next.label,
        windowKey: window.key,
        windowLabel: window.label,
        fromUsed: before.usedPercent,
        toUsed: window.usedPercent,
        remainingPercent: window.remainingPercent,
      });
      continue;
    }
    if (dropped >= 3) {
      events.push({
        id: `${windowEventId(next.id, window, 'refill')}:${Math.round(before.usedPercent)}-${Math.round(window.usedPercent)}`,
        at: nowIso,
        kind: 'refill',
        accountId: next.id,
        provider: next.provider,
        label: next.label,
        windowKey: window.key,
        windowLabel: window.label,
        fromUsed: before.usedPercent,
        toUsed: window.usedPercent,
        remainingPercent: window.remainingPercent,
      });
      continue;
    }
    const wasAbove = before.remainingPercent > lowThreshold;
    const nowBelow = window.remainingPercent <= lowThreshold;
    const freshWindow = beforeReset !== undefined && nextReset !== undefined
      ? Math.abs(nextReset - beforeReset) > 60_000
      : before.resetsAt !== window.resetsAt;
    if (nowBelow && (wasAbove || freshWindow)) {
      events.push({
        id: windowEventId(next.id, window, 'low'),
        at: nowIso,
        kind: 'low',
        accountId: next.id,
        provider: next.provider,
        label: next.label,
        windowKey: window.key,
        windowLabel: window.label,
        fromUsed: before.usedPercent,
        toUsed: window.usedPercent,
        remainingPercent: window.remainingPercent,
      });
    }
  }
  return events;
}

/**
 * Replace the account table with this collection's snapshots and append any
 * reset/refill/low transitions. Returns the events added in this pass.
 */
export function mergeCollection(state, results, { now = Date.now(), lowThreshold = 10, diag = {}, replace = true } = {}) {
  const nowIso = new Date(now).toISOString();
  const accounts = replace ? {} : { ...state.accounts };
  const added = [];
  const seen = new Set(state.events.map((event) => event.id));

  for (const result of results) {
    if (!result || !result.id) continue;
    accounts[result.id] = result;
    const previous = state.accounts[result.id];
    if (!previous || result.status === 'error' || result.status === 'auth') continue;
    for (const event of detectEvents(previous, result, lowThreshold, nowIso)) {
      if (seen.has(event.id)) continue;
      seen.add(event.id);
      added.push(event);
    }
  }

  const events = [...state.events, ...added].slice(-50);
  return {
    state: {
      ...state,
      updatedAt: nowIso,
      accounts,
      events,
      diag: { ...state.diag, ...diag, lastCollectAt: nowIso },
    },
    added,
  };
}
