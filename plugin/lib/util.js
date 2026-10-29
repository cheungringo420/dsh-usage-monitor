/** Small pure helpers shared by the Host half. No I/O, no secrets. */

export function clamp(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return min;
  return Math.min(max, Math.max(min, n));
}

export function round1(value) {
  return Math.round(value * 10) / 10;
}

export function asNumber(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : undefined;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

/** Epoch seconds, epoch milliseconds, or ISO text -> epoch milliseconds. */
export function parseDateMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value > 1e12 ? value : value * 1000;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? undefined : ms;
  }
  return undefined;
}

export function isoFromMs(ms) {
  return Number.isFinite(ms) ? new Date(ms).toISOString() : undefined;
}

/** Stable key for a quota window, derived from its declared duration. */
export function windowKey(seconds, fallback = 'window') {
  if (!Number.isFinite(seconds)) return fallback;
  const known = [
    [5 * 60 * 60, '5h'],
    [24 * 60 * 60, 'day'],
    [7 * 24 * 60 * 60, 'week'],
    [30 * 24 * 60 * 60, 'month'],
  ];
  for (const [duration, key] of known) {
    if (Math.abs(seconds - duration) <= 120) return key;
  }
  return `w${Math.round(seconds / 3600)}h`;
}

export function windowLabel(seconds, fallback = 'Window') {
  if (!Number.isFinite(seconds)) return fallback;
  if (Math.abs(seconds - 18000) <= 120) return '5-hour';
  if (Math.abs(seconds - 86400) <= 120) return 'Daily';
  if (Math.abs(seconds - 604800) <= 120) return 'Weekly';
  if (Math.abs(seconds - 2592000) <= 120) return 'Monthly';
  const hours = Math.round(seconds / 3600);
  return hours >= 48 ? `${Math.round(hours / 24)}-day` : `${hours}-hour`;
}

/** Keep diagnostics useful without echoing a credential. */
export function sanitizeMessage(error) {
  let text = error instanceof Error ? error.message : String(error ?? 'unknown error');
  text = text
    .replace(/(authorization\s*[:=]\s*)(bearer\s+)?[A-Za-z0-9._~+/=-]{8,}/gi, '$1***')
    .replace(/((?:access|refresh|id)[_-]?token|api[_-]?key|secret|password)\s*["'=:\s]+[A-Za-z0-9._~+/=-]{8,}/gi, '$1=***')
    .replace(/\b[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b/g, '***')
    .replace(/\s+/g, ' ')
    .trim();
  return text.slice(0, 200);
}

export function stableHash(input) {
  let hash = 0x811c9dc5;
  const text = String(input);
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

export function escapeAppleScript(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\r\n]+/g, ' ');
}
