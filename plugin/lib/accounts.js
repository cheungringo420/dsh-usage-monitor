/** Account discovery. Credentials are read from local stores and kept in memory only. */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import { asNumber, stableHash } from './util.js';

const execFileAsync = promisify(execFile);
const CLAUDE_KEYCHAIN_SERVICE = 'Claude Code-credentials';
const CLAUDE_CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const CLAUDE_TOKEN_URL = 'https://platform.claude.com/v1/oauth/token';
const KEYCHAIN_TTL_MS = 10 * 60 * 1000;
const TOKEN_REFRESH_SKEW_MS = 2 * 60 * 1000;

let claudeKeychainCache = { at: 0, value: undefined };

function homePath(...parts) {
  return path.join(os.homedir(), ...parts);
}

function readJsonFile(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return undefined;
  }
}

function readTextFile(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return undefined;
  }
}

function expandHome(value) {
  if (typeof value !== 'string') return value;
  if (value === '~') return os.homedir();
  if (value.startsWith('~/')) return path.join(os.homedir(), value.slice(2));
  return path.resolve(value);
}

function decodeJwtPayload(token) {
  if (typeof token !== 'string') return undefined;
  const part = token.split('.')[1];
  if (!part) return undefined;
  try {
    return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
  } catch {
    return undefined;
  }
}

/**
 * Codex tokens carry the real per-user identity. CC Switch rows for two
 * different people can share the team account id, so the user id, not the
 * stored account id, decides whether two rows are the same account.
 */
function codexIdentity(token, fallbackAccountId) {
  const claims = decodeJwtPayload(token) || {};
  const auth = claims['https://api.openai.com/auth'] || {};
  const profile = claims['https://api.openai.com/profile'] || {};
  return {
    email: typeof claims.email === 'string' ? claims.email : typeof profile.email === 'string' ? profile.email : undefined,
    userId: typeof auth.chatgpt_user_id === 'string' ? auth.chatgpt_user_id : typeof auth.user_id === 'string' ? auth.user_id : undefined,
    teamId: typeof auth.chatgpt_account_id === 'string' ? auth.chatgpt_account_id : fallbackAccountId,
    plan: typeof auth.chatgpt_plan_type === 'string' ? auth.chatgpt_plan_type : undefined,
    expiresAt: typeof claims.exp === 'number' ? claims.exp : undefined,
  };
}

/** Accept a raw token file or any of the JSON shapes the CLIs use. */
function tokenFromText(text) {
  if (typeof text !== 'string') return undefined;
  const trimmed = text.trim();
  if (!trimmed) return undefined;
  if (trimmed.startsWith('{')) {
    try {
      const value = JSON.parse(trimmed);
      const candidates = [
        value.key,
        value.access_token,
        value.tokens && value.tokens.access_token,
        value.claudeAiOauth && value.claudeAiOauth.accessToken,
      ];
      for (const candidate of candidates) {
        if (typeof candidate === 'string' && candidate.trim()) return candidate.trim();
      }
      for (const entry of Object.values(value)) {
        if (entry && typeof entry === 'object' && typeof entry.key === 'string' && entry.key.trim()) {
          return entry.key.trim();
        }
      }
    } catch {
      // fall through: treat as a raw token
    }
  }
  return trimmed.split(/\s+/)[0];
}

function codexAccountFromAuth(auth, { source, label }) {
  if (!auth || auth.auth_mode !== 'chatgpt') return undefined;
  const tokens = auth.tokens || {};
  const token = typeof tokens.access_token === 'string' ? tokens.access_token : undefined;
  if (!token) return undefined;
  const info = codexIdentity(token, typeof tokens.account_id === 'string' ? tokens.account_id : undefined);
  const identity = info.userId || info.email || info.teamId || stableHash(`${source}:${label || 'codex'}`);
  return {
    id: `codex:${identity}`,
    provider: 'codex',
    source,
    label: info.email || label || 'Codex',
    email: info.email,
    token,
    accountId: info.teamId,
    plan: info.plan,
    expiresAt: info.expiresAt,
  };
}

function codexHomes() {
  const homes = [process.env.CODEX_HOME || homePath('.codex')];
  try {
    for (const entry of fs.readdirSync(os.homedir())) {
      if (entry.startsWith('.codex-') && entry !== '.codex-auth') {
        const candidate = homePath(entry);
        if (fs.existsSync(path.join(candidate, 'auth.json'))) homes.push(candidate);
      }
    }
  } catch {
    // ignore an unreadable home directory
  }
  return [...new Set(homes)];
}

function codexAccounts() {
  const accounts = [];
  for (const home of codexHomes()) {
    const auth = readJsonFile(path.join(home, 'auth.json'));
    const account = codexAccountFromAuth(auth, { source: 'cli', label: home === homePath('.codex') ? 'Codex CLI' : `Codex (${path.basename(home)})` });
    if (account) accounts.push(account);
  }
  return accounts;
}

function grokAccounts() {
  const home = process.env.GROK_HOME || homePath('.grok');
  const auth = readJsonFile(path.join(home, 'auth.json'));
  if (!auth || typeof auth !== 'object') return [];
  const accounts = [];
  for (const [entryKey, entry] of Object.entries(auth)) {
    if (!entry || typeof entry !== 'object') continue;
    const token = typeof entry.key === 'string' ? entry.key.trim() : '';
    if (!token) continue;
    const identity = entry.principal_id || entry.user_id || entry.email || entryKey;
    const id = `grok:${identity}`;
    if (accounts.some((account) => account.id === id)) continue;
    accounts.push({
      id,
      provider: 'grok',
      source: 'cli',
      label: entry.email || entry.first_name || 'Grok CLI',
      email: typeof entry.email === 'string' ? entry.email : undefined,
      token,
      identity,
      plan: entry.principal_type === 'Team' ? 'Team' : undefined,
    });
  }
  return accounts;
}

async function ccSwitchAccounts() {
  const db = homePath('.cc-switch', 'cc-switch.db');
  if (!fs.existsSync(db)) return [];
  let rows;
  try {
    const result = await execFileAsync(
      'sqlite3',
      ['-readonly', '-json', db, "SELECT name, settings_config FROM providers WHERE app_type = 'codex'"],
      { timeout: 8000, maxBuffer: 8 * 1024 * 1024 },
    );
    rows = JSON.parse(result.stdout || '[]');
  } catch {
    return [];
  }
  if (!Array.isArray(rows)) return [];
  const accounts = [];
  for (const row of rows) {
    let settings;
    try {
      settings = typeof row.settings_config === 'string' ? JSON.parse(row.settings_config) : row.settings_config;
    } catch {
      continue;
    }
    if (!settings || typeof settings !== 'object') continue;
    const auth = typeof settings.auth === 'string' ? (() => {
      try {
        return JSON.parse(settings.auth);
      } catch {
        return undefined;
      }
    })() : settings.auth;
    const tokens = auth && typeof auth === 'object' ? auth.tokens : undefined;
    const token = tokens && typeof tokens.access_token === 'string' ? tokens.access_token : undefined;
    if (!token) continue;
    const info = codexIdentity(token, typeof tokens.account_id === 'string' ? tokens.account_id : undefined);
    if (info.expiresAt && info.expiresAt * 1000 < Date.now() + 60_000) continue;
    const identity = info.userId || info.email || info.teamId || stableHash(`cc-switch:${row.name}`);
    const id = `codex:${identity}`;
    if (accounts.some((account) => account.id === id)) continue;
    accounts.push({
      id,
      provider: 'codex',
      source: 'cc-switch',
      label: info.email || row.name || 'Codex account',
      email: info.email,
      token,
      accountId: info.teamId,
      plan: info.plan,
      expiresAt: info.expiresAt,
    });
  }
  return accounts;
}

async function readClaudeKeychainFull() {
  if (process.platform !== 'darwin') return undefined;
  const result = await execFileAsync(
    'security',
    ['find-generic-password', '-s', CLAUDE_KEYCHAIN_SERVICE, '-w'],
    { timeout: 5000, maxBuffer: 2 * 1024 * 1024 },
  );
  const parsed = JSON.parse(result.stdout || '{}');
  return parsed && typeof parsed === 'object' ? parsed : undefined;
}

async function claudeKeychainAccount() {
  try {
    const result = await execFileAsync(
      'security',
      ['find-generic-password', '-s', CLAUDE_KEYCHAIN_SERVICE],
      { timeout: 5000, maxBuffer: 2 * 1024 * 1024 },
    );
    const match = /"acct"<blob>="([^"]*)"/.exec(result.stdout || '');
    return match && match[1] ? match[1] : os.userInfo().username;
  } catch {
    return os.userInfo().username;
  }
}

async function writeClaudeKeychain(full) {
  const account = await claudeKeychainAccount();
  await execFileAsync(
    'security',
    ['add-generic-password', '-U', '-s', CLAUDE_KEYCHAIN_SERVICE, '-a', account, '-w', JSON.stringify(full)],
    { timeout: 8000, maxBuffer: 2 * 1024 * 1024 },
  );
}

async function refreshClaudeOAuth(oauth, full) {
  const response = await fetch(CLAUDE_TOKEN_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      accept: 'application/json',
      'user-agent': 'claude-cli/2.1.310',
    },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: oauth.refreshToken,
      client_id: CLAUDE_CLIENT_ID,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const text = await response.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = undefined;
  }
  if (!response.ok || !data || typeof data.access_token !== 'string') {
    const error = new Error(`Claude token refresh failed (HTTP ${response.status})`);
    error.kind = 'auth';
    throw error;
  }
  const now = Date.now();
  oauth.accessToken = data.access_token;
  oauth.expiresAt = now + (asNumber(data.expires_in) ?? 28_800) * 1000;
  if (typeof data.refresh_token === 'string' && data.refresh_token) oauth.refreshToken = data.refresh_token;
  const refreshExpiresIn = asNumber(data.refresh_token_expires_in);
  if (refreshExpiresIn) oauth.refreshTokenExpiresAt = now + refreshExpiresIn * 1000;
  full.claudeAiOauth = oauth;
  await writeClaudeKeychain(full);
  claudeKeychainCache = { at: Date.now(), value: oauth };
  return oauth;
}

/**
 * Refresh the Keychain Claude Code access token when it is near expiry (or
 * after a 401), writing the rotated tokens back so Claude Code stays in sync.
 */
export async function ensureClaudeToken(account, { force = false } = {}) {
  if (!account || account.provider !== 'claude' || !account.keychain || !account.refreshToken) return account;
  const now = Date.now();
  if (!force && account.expiresAt && account.expiresAt > now + TOKEN_REFRESH_SKEW_MS) return account;

  let full;
  try {
    full = await readClaudeKeychainFull();
  } catch {
    return account;
  }
  const oauth = full && full.claudeAiOauth;
  if (!oauth || typeof oauth.refreshToken !== 'string' || !oauth.refreshToken) return account;

  const expiry = asNumber(oauth.expiresAt);
  if (oauth.accessToken && oauth.accessToken !== account.token && expiry && expiry > now + 60_000) {
    claudeKeychainCache = { at: Date.now(), value: oauth };
    return {
      ...account,
      token: oauth.accessToken,
      refreshToken: oauth.refreshToken,
      expiresAt: expiry,
    };
  }
  if (!force && expiry && expiry > now + TOKEN_REFRESH_SKEW_MS) {
    claudeKeychainCache = { at: Date.now(), value: oauth };
    return {
      ...account,
      token: oauth.accessToken || account.token,
      refreshToken: oauth.refreshToken,
      expiresAt: expiry,
    };
  }

  const refreshed = await refreshClaudeOAuth(oauth, full);
  return {
    ...account,
    token: refreshed.accessToken,
    refreshToken: refreshed.refreshToken,
    expiresAt: refreshed.expiresAt,
  };
}

async function claudeKeychainOAuth() {
  if (process.platform !== 'darwin') return undefined;
  if (Date.now() - claudeKeychainCache.at < KEYCHAIN_TTL_MS) return claudeKeychainCache.value;
  let value;
  try {
    const full = await readClaudeKeychainFull();
    value = full && typeof full.claudeAiOauth === 'object' ? full.claudeAiOauth : undefined;
  } catch {
    value = undefined;
  }
  // Cache a successful read, but never a miss: after a sign-in the next
  // collect should see the token immediately instead of waiting for the TTL.
  claudeKeychainCache = value ? { at: Date.now(), value } : { at: 0, value: undefined };
  return value;
}

function claudeOAuthAccount(oauth, { source, label, keychain = false }) {
  if (!oauth || typeof oauth !== 'object') return undefined;
  const token = typeof oauth.accessToken === 'string' ? oauth.accessToken.trim() : '';
  if (!token) return undefined;
  const email = typeof oauth.accountEmail === 'string' ? oauth.accountEmail
    : typeof oauth.emailAddress === 'string' ? oauth.emailAddress
      : typeof oauth.email === 'string' ? oauth.email : undefined;
  const identity = email || 'code';
  return {
    id: `claude:${identity}`,
    provider: 'claude',
    source,
    label: email || label || 'Claude Code',
    email,
    token,
    identity: 'claude-code',
    plan: typeof oauth.subscriptionType === 'string' ? oauth.subscriptionType : undefined,
    keychain,
    refreshToken: typeof oauth.refreshToken === 'string' ? oauth.refreshToken : undefined,
    expiresAt: asNumber(oauth.expiresAt),
    refreshTokenExpiresAt: asNumber(oauth.refreshTokenExpiresAt),
  };
}

async function claudeAccounts() {
  const candidates = [];
  const keychain = await claudeKeychainOAuth();
  if (keychain) candidates.push(claudeOAuthAccount(keychain, { source: 'cli', label: 'Claude Code', keychain: true }));

  const file = readJsonFile(homePath('.claude', '.credentials.json'));
  if (file && file.claudeAiOauth) {
    candidates.push(claudeOAuthAccount(file.claudeAiOauth, { source: 'cli', label: 'Claude Code' }));
  }

  const envToken = process.env.CLAUDE_CODE_OAUTH_TOKEN;
  if (typeof envToken === 'string' && envToken.trim()) {
    candidates.push(claudeOAuthAccount({ accessToken: envToken.trim() }, { source: 'cli', label: 'Claude Code' }));
  }

  return candidates.filter(Boolean);
}

function claudePlaceholder() {
  return {
    id: 'claude:not-signed-in',
    provider: 'claude',
    source: 'cli',
    label: 'Claude Code',
    token: '',
    placeholder: true,
  };
}

function manualAccounts(config) {
  const entries = Array.isArray(config.accounts) ? config.accounts : [];
  const accounts = [];
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object') continue;
    const provider = entry.provider;
    if (provider !== 'codex' && provider !== 'grok' && provider !== 'claude') continue;
    let token;
    if (typeof entry.tokenEnv === 'string' && entry.tokenEnv) {
      token = process.env[entry.tokenEnv];
    }
    if (!token && typeof entry.tokenFile === 'string' && entry.tokenFile) {
      token = tokenFromText(readTextFile(expandHome(entry.tokenFile)));
    }
    if (!token) continue;
    const info = provider === 'codex' ? codexIdentity(token, typeof entry.accountId === 'string' ? entry.accountId : undefined) : {};
    const accountId = typeof entry.accountId === 'string' ? entry.accountId : info.teamId;
    const label = typeof entry.label === 'string' && entry.label ? entry.label : `${provider} account`;
    const identity = entry.id || info.userId || info.email || accountId || stableHash(`${provider}:${label}`);
    accounts.push({
      id: `${provider}:${identity}`,
      provider,
      source: 'manual',
      label: info.email || label,
      token,
      accountId,
      identity: entry.id || identity,
      plan: typeof entry.plan === 'string' ? entry.plan : info.plan,
      email: info.email || (typeof entry.email === 'string' ? entry.email : undefined),
    });
  }
  return accounts;
}

const SOURCE_PRIORITY = { manual: 3, cli: 2, 'cc-switch': 1 };

function dedupe(accounts) {
  const byId = new Map();
  for (const account of accounts) {
    const existing = byId.get(account.id);
    if (!existing) {
      byId.set(account.id, account);
      continue;
    }
    const nextPriority = SOURCE_PRIORITY[account.source] || 0;
    const currentPriority = SOURCE_PRIORITY[existing.source] || 0;
    byId.set(account.id, nextPriority > currentPriority ? { ...existing, ...account } : { ...account, ...existing });
  }
  return [...byId.values()];
}

/** Resolve every account available on this machine from the enabled sources. */
export async function discoverAccounts(config) {
  const accounts = [];
  const discovery = config.discovery || {};
  if (discovery.cli !== false) {
    accounts.push(...codexAccounts());
    accounts.push(...grokAccounts());
    accounts.push(...(await claudeAccounts()));
  }
  if (discovery.ccSwitch !== false) {
    accounts.push(...(await ccSwitchAccounts()));
  }
  accounts.push(...manualAccounts(config));
  const resolved = dedupe(accounts);
  if (!resolved.some((account) => account.provider === 'claude' && !account.placeholder)) {
    resolved.push(claudePlaceholder());
  }
  return resolved;
}

export { tokenFromText };
