window.__ModuleLoader__.load({
  id: '@local/usage-monitor',
  factory(require) {
    const React = require('react');
    const h = React.createElement;

    const NS = 'usage-monitor';
    const PANEL_ID = 'usage-monitor';
    const SEEN_KEY = 'dsh.usage-monitor.seen.v1';

    const EN = {
      panel: 'Usage Monitor',
      subtitle: 'Remaining quota across every Codex and Grok account',
      refresh: 'Refresh',
      refreshing: 'Refreshing',
      updated: 'Updated',
      justNow: 'just now',
      minutesAgo: '{n}m ago',
      autoRefresh: 'Auto-refreshes every {n} min',
      fiveHour: '5-hour',
      daily: 'Daily',
      weekly: 'Weekly',
      monthly: 'Monthly',
      opus: 'Opus',
      sonnet: 'Sonnet',
      extraUsage: 'Extra usage',
      window: 'Window',
      remaining: '{n}% left',
      used: '{n}% used',
      resetsAt: '{time} reset',
      resetIn: 'in {duration}',
      resetsSoon: 'resetting now',
      exhausted: 'Exhausted',
      low: 'Low',
      ok: 'Live',
      stale: 'Stale',
      signIn: 'Sign in again',
      unavailable: 'Unavailable',
      loading: 'Reading usage…',
      emptyTitle: 'No accounts found',
      emptyBody: 'Sign in with the Codex, Claude or Grok CLI, or add an account in the plugin config.',
      errorTitle: 'Could not load usage',
      retry: 'Retry',
      codex: 'Codex',
      claude: 'Claude',
      grok: 'Grok',
      accounts: 'accounts',
      plan: 'Plan',
      credits: 'Credits',
      products: 'Breakdown',
      privacy: 'Credentials are read locally and never leave this machine except to the provider’s own usage endpoint.',
      source_cli: 'CLI',
      source_ccSwitch: 'CC Switch',
      source_manual: 'Manual',
      resetToast: '{name} quota reset',
      refillToast: '{name} quota refilled',
      lowToast: '{name} running low',
      toastResetBody: '{window}: {from}% → {to}% used',
      toastRefillBody: '{window}: {from}% → {to}% used',
      toastLowBody: '{window}: {remaining}% remaining',
      signInHint: 'Run `{cmd}` to sign in again.',
      dismiss: 'Dismiss',
      openPanel: 'Open Usage Monitor',
      close: 'Close',
      unlimited: 'Unlimited',
      overage: 'Overage',
      noAccounts: 'No accounts',
    };

    const ZH = {
      panel: '用量監控',
      subtitle: '集中查看所有 Codex 與 Grok 帳號的剩餘額度',
      refresh: '重新整理',
      refreshing: '更新中',
      updated: '更新於',
      justNow: '剛剛',
      minutesAgo: '{n} 分鐘前',
      autoRefresh: '每 {n} 分鐘自動更新',
      fiveHour: '5 小時',
      daily: '每日',
      weekly: '本週',
      monthly: '每月',
      opus: 'Opus',
      sonnet: 'Sonnet',
      extraUsage: '額外用量',
      window: '週期',
      remaining: '剩餘 {n}%',
      used: '已使用 {n}%',
      resetsAt: '{time} 重設',
      resetIn: '{duration}後',
      resetsSoon: '即將重設',
      exhausted: '已用完',
      low: '偏低',
      ok: '正常',
      stale: '資料過舊',
      signIn: '請重新登入',
      unavailable: '無法取得',
      loading: '正在讀取用量…',
      emptyTitle: '找不到帳號',
      emptyBody: '請先登入 Codex、Claude 或 Grok CLI，或在外掛設定中新增帳號。',
      errorTitle: '無法載入用量',
      retry: '重試',
      codex: 'Codex',
      claude: 'Claude',
      grok: 'Grok',
      accounts: '個帳號',
      plan: '方案',
      credits: '額度',
      products: '細項',
      privacy: '憑證只在本機讀取，除提供商自身的用量端點外不會離開這台電腦。',
      source_cli: 'CLI',
      source_ccSwitch: 'CC Switch',
      source_manual: '手動',
      resetToast: '{name} 額度已重設',
      refillToast: '{name} 額度已補充',
      lowToast: '{name} 額度偏低',
      toastResetBody: '{window}：已使用 {from}% → {to}%',
      toastRefillBody: '{window}：已使用 {from}% → {to}%',
      toastLowBody: '{window}：剩餘 {remaining}%',
      signInHint: '請執行 `{cmd}` 重新登入。',
      dismiss: '關閉',
      openPanel: '開啟用量監控',
      close: '關閉',
      unlimited: '無上限',
      overage: '超額使用',
      noAccounts: '沒有帳號',
    };

    function fill(template, vars) {
      return String(template).replace(/\{(\w+)\}/g, (_match, key) =>
        vars && vars[key] !== undefined && vars[key] !== null ? String(vars[key]) : '',
      );
    }

    function clampPercent(value) {
      const number = Number(value);
      if (!Number.isFinite(number)) return 0;
      return Math.min(100, Math.max(0, number));
    }

    function levelFor(remaining) {
      if (remaining <= 10) return 'danger';
      if (remaining <= 30) return 'warn';
      return 'ok';
    }

    function providerColor(provider) {
      if (provider === 'codex') return '#10a37f';
      if (provider === 'claude') return '#d97757';
      if (provider === 'grok') return '#374151';
      return 'var(--dsw-alias-brand-primary)';
    }

    function providerInitial(provider) {
      if (provider === 'codex') return 'C';
      if (provider === 'claude') return 'A';
      if (provider === 'grok') return 'G';
      return '?';
    }

    function windowLabel(window, i18n) {
      if (window.key === '5h') return i18n.t('fiveHour');
      if (window.key === 'week') return i18n.t('weekly');
      if (window.key === 'day') return i18n.t('daily');
      if (window.key === 'month') return i18n.t('monthly');
      if (window.key === 'opus') return i18n.t('opus');
      if (window.key === 'sonnet') return i18n.t('sonnet');
      if (window.key === 'extra') return i18n.t('extraUsage');
      return window.label || i18n.t('window');
    }

    function durationShort(ms) {
      const minutes = Math.max(0, Math.round(ms / 60000));
      if (minutes < 1) return '<1m';
      const days = Math.floor(minutes / 1440);
      const hours = Math.floor((minutes % 1440) / 60);
      const rest = minutes % 60;
      if (days > 0) return `${days}d ${hours}h`;
      if (hours > 0) return `${hours}h ${rest}m`;
      return `${rest}m`;
    }

    function durationLong(ms, zh) {
      const minutes = Math.max(0, Math.round(ms / 60000));
      if (minutes < 1) return zh ? '不到 1 分鐘' : 'less than a minute';
      const days = Math.floor(minutes / 1440);
      const hours = Math.floor((minutes % 1440) / 60);
      const rest = minutes % 60;
      const parts = [];
      if (days) parts.push(zh ? `${days} 天` : `${days}d`);
      if (hours) parts.push(zh ? `${hours} 小時` : `${hours}h`);
      if (rest && !days) parts.push(zh ? `${rest} 分鐘` : `${rest}m`);
      return parts.join(' ');
    }

    const formatterCache = new Map();

    function whenFormatter(zh, mode) {
      const key = `${zh ? 'zh' : 'en'}:${mode}`;
      if (formatterCache.has(key)) return formatterCache.get(key);
      const locale = zh ? 'zh-TW' : 'en-US';
      const options =
        mode === 'date'
          ? { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
          : mode === 'time'
            ? { hour: '2-digit', minute: '2-digit' }
            : { weekday: 'short', hour: '2-digit', minute: '2-digit' };
      const formatter = new Intl.DateTimeFormat(locale, options);
      formatterCache.set(key, formatter);
      return formatter;
    }

    function formatWhen(iso, zh, now) {
      const ms = Date.parse(iso);
      if (Number.isNaN(ms)) return '';
      const sameDay = new Date(ms).toDateString() === new Date(now).toDateString();
      const mode = ms - now > 6 * 24 * 60 * 60 * 1000 ? 'date' : sameDay ? 'time' : 'weekday';
      return whenFormatter(zh, mode).format(new Date(ms));
    }

    function resetText(window, i18n, now) {
      if (!window.resetsAt) return '';
      const ms = Date.parse(window.resetsAt);
      if (Number.isNaN(ms)) return '';
      if (ms <= now) return i18n.t('resetsSoon');
      return `${i18n.s('resetsAt', { time: formatWhen(window.resetsAt, i18n.zh(), now) })} · ${i18n.s('resetIn', {
        duration: durationLong(ms - now, i18n.zh()),
      })}`;
    }

    function loadSeen() {
      try {
        const raw = JSON.parse(window.localStorage.getItem(SEEN_KEY) || '[]');
        return new Set(Array.isArray(raw) ? raw : []);
      } catch {
        return new Set();
      }
    }

    function saveSeen(seen) {
      try {
        window.localStorage.setItem(SEEN_KEY, JSON.stringify([...seen].slice(-200)));
      } catch {
        // storage can be unavailable; toasts still work for this page
      }
    }

    function apiUrl(path) {
      const suffix = `/api/usage-monitor/${path}`;
      try {
        const transport = window.__DSH_TRANSPORT__;
        const base = transport && (transport.streamBaseUrl || transport.baseUrl);
        if (base) {
          const url = new URL(suffix, base);
          if (url.protocol === 'ws:') url.protocol = 'http:';
          if (url.protocol === 'wss:') url.protocol = 'https:';
          return url.toString();
        }
      } catch {
        // fall through to the same-origin path
      }
      return suffix;
    }

    function createStore(ctx) {
      let snapshot = { loading: true, refreshing: false, data: null, error: null, toasts: [], localeRev: 0, now: Date.now() };
      const listeners = new Set();
      let inflight = null;
      const seen = loadSeen();

      const emit = () => {
        for (const listener of listeners) {
          try {
            listener();
          } catch {
            // a broken subscriber must not break the others
          }
        }
      };
      const set = (patch) => {
        snapshot = { ...snapshot, ...patch };
        emit();
      };
      const subscribe = (listener) => {
        listeners.add(listener);
        return () => listeners.delete(listener);
      };

      async function request(path, options) {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 20_000);
        const { headers, ...rest } = options || {};
        try {
          const response = await fetch(apiUrl(path), {
            cache: 'no-store',
            credentials: 'same-origin',
            ...rest,
            headers: { accept: 'application/json', ...headers },
            signal: controller.signal,
          });
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          return await response.json();
        } finally {
          clearTimeout(timer);
        }
      }

      function ingest(data) {
        const events = Array.isArray(data.events) ? data.events : [];
        const now = Date.now();
        const fresh = events.filter((event) => {
          const at = Date.parse(event.at);
          return Number.isFinite(at) && now - at < 2 * 60 * 60 * 1000 && !seen.has(event.id);
        });
        if (fresh.length) {
          for (const event of fresh) seen.add(event.id);
          saveSeen(seen);
        }
        const allowToast = !data.ui || data.ui.toast !== false;
        const toasts = [...snapshot.toasts];
        if (allowToast) {
          for (const event of fresh) toasts.push({ ...event, key: event.id });
        }
        set({ loading: false, data, error: null, toasts: toasts.slice(-3), now });
      }

      async function load() {
        if (inflight) return inflight;
        inflight = (async () => {
          try {
            ingest(await request('state'));
          } catch (error) {
            set({ loading: false, error: error && error.message ? error.message : String(error) });
          } finally {
            inflight = null;
          }
        })();
        return inflight;
      }

      async function refresh() {
        if (inflight) {
          set({ refreshing: true });
          try {
            return await inflight;
          } finally {
            set({ refreshing: false });
          }
        }
        set({ refreshing: true });
        inflight = (async () => {
          try {
            ingest(await request('refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }));
            set({ refreshing: false });
          } catch (error) {
            set({ refreshing: false, error: error && error.message ? error.message : String(error) });
          } finally {
            inflight = null;
          }
        })();
        return inflight;
      }

      function dismiss(key) {
        set({ toasts: snapshot.toasts.filter((toast) => toast.key !== key) });
      }

      function bumpLocale() {
        set({ localeRev: snapshot.localeRev + 1 });
      }

      function localeTag() {
        try {
          return String(ctx.locale.getLocale().active || 'en').toLowerCase().startsWith('zh') ? 'zh-TW' : 'en-US';
        } catch {
          return 'en-US';
        }
      }

      function start() {
        load();
        let tick = 0;
        const timer = setInterval(() => {
          tick += 1;
          set({ now: Date.now() });
          if (tick % 2 === 0 && !document.hidden) load();
        }, 30_000);
        const onVisible = () => {
          if (!document.hidden) {
            set({ now: Date.now() });
            load();
          }
        };
        document.addEventListener('visibilitychange', onVisible);
        return () => {
          clearInterval(timer);
          document.removeEventListener('visibilitychange', onVisible);
        };
      }

      return {
        subscribe,
        getSnapshot: () => snapshot,
        load,
        refresh,
        dismiss,
        bumpLocale,
        start,
        localeTag,
      };
    }

    function Styles() {
      return h('style', { 'data-dsh-usage-monitor': 'styles' }, CSS);
    }

    function RefreshIcon({ size = 14 }) {
      return h(
        'svg',
        { viewBox: '0 0 16 16', width: size, height: size, fill: 'none', 'aria-hidden': true },
        h('path', {
          d: 'M13.2 8a5.2 5.2 0 1 1-1.6-3.7',
          stroke: 'currentColor',
          strokeWidth: 1.6,
          strokeLinecap: 'round',
        }),
        h('path', {
          d: 'M13.4 2.4v3.4H10',
          stroke: 'currentColor',
          strokeWidth: 1.6,
          strokeLinecap: 'round',
          strokeLinejoin: 'round',
        }),
      );
    }

    function GaugeIcon({ size = 18 }) {
      return h(
        'svg',
        { viewBox: '0 0 24 24', width: size, height: size, fill: 'none', 'aria-hidden': true, className: 'dsh-um-gauge' },
        h('rect', { x: 3, y: 6, width: 13, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.95 }),
        h('rect', { x: 3, y: 10.5, width: 9.5, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.7 }),
        h('rect', { x: 3, y: 15, width: 6, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.45 }),
        h('circle', { cx: 19, cy: 16.5, r: 2, fill: 'currentColor', opacity: 0.55 }),
      );
    }

    function worstWindows(accounts) {
      const rows = [];
      for (const account of accounts || []) {
        for (const window of account.windows || []) {
          if (typeof window.remainingPercent !== 'number') continue;
          rows.push({ account, window });
        }
      }
      return rows.sort((left, right) => left.window.remainingPercent - right.window.remainingPercent);
    }

    function accountStale(account, data, now) {
      const updated = Date.parse(account.updatedAt || '');
      if (Number.isNaN(updated)) return false;
      const poll = data && data.ui && data.ui.pollSeconds ? data.ui.pollSeconds : 300;
      return now - updated > Math.max(120_000, poll * 2000);
    }

    function statusOf(account, i18n, stale) {
      if (account.status === 'auth') return { label: i18n.t('signIn'), level: 'danger' };
      if (account.status === 'error') return { label: i18n.t('unavailable'), level: 'danger' };
      if (stale) return { label: i18n.t('stale'), level: 'warn' };
      const min = (account.windows || []).reduce(
        (value, window) => Math.min(value, clampPercent(window.remainingPercent)),
        100,
      );
      if (min <= 10) return { label: i18n.t('low'), level: 'warn' };
      return { label: i18n.t('ok'), level: 'ok' };
    }

    function WindowRow({ account, window, i18n, now }) {
      const remaining = clampPercent(window.remainingPercent);
      const level = levelFor(remaining);
      const reset = resetText(window, i18n, now);
      return h(
        'div',
        { className: 'dsh-um-window' },
        h(
          'div',
          { className: 'dsh-um-window-head' },
          h('span', { className: 'dsh-um-window-label' }, windowLabel(window, i18n)),
          h('span', { className: 'dsh-um-window-value' }, i18n.s('remaining', { n: Math.round(remaining) })),
          h('span', { className: 'dsh-um-window-used' }, i18n.s('used', { n: Math.round(Number(window.usedPercent) || 0) })),
        ),
        h(
          'div',
          {
            className: 'dsh-um-bar',
            role: 'progressbar',
            'aria-valuemin': 0,
            'aria-valuemax': 100,
            'aria-valuenow': Math.round(remaining),
            'aria-label': `${account.label} ${windowLabel(window, i18n)}`,
          },
          h('div', { className: `dsh-um-bar-fill is-${level}`, style: { width: `${remaining}%` } }),
        ),
        reset ? h('div', { className: 'dsh-um-window-meta' }, reset) : null,
      );
    }

    function Extras({ account, i18n }) {
      const extras = account.extras || [];
      if (!extras.length) return null;
      return h(
        'div',
        { className: 'dsh-um-extras' },
        extras.map((extra, index) => {
          if (Array.isArray(extra.items) && extra.items.length) {
            return h(
              'div',
              { className: 'dsh-um-products', key: `products-${index}` },
              h('span', { className: 'dsh-um-extras-label' }, i18n.t('products')),
              extra.items.map((item) =>
                h(
                  'span',
                  { className: 'dsh-um-product', key: item.label },
                  h('span', null, item.label),
                  h('b', null, `${Math.round(item.usedPercent)}%`),
                ),
              ),
            );
          }
          if (!extra.value) return null;
          return h(
            'div',
            { className: `dsh-um-extra${extra.kind === 'warning' ? ' is-warning' : ''}`, key: `text-${index}` },
            h('span', { className: 'dsh-um-extras-label' }, extra.label),
            h('strong', null, extra.value),
          );
        }),
      );
    }

    function AccountCard({ account, i18n, now, stale }) {
      const status = statusOf(account, i18n, stale);
      const sourceKey =
        account.source === 'cc-switch'
          ? 'source_ccSwitch'
          : account.source === 'cli'
            ? 'source_cli'
            : account.source === 'manual'
              ? 'source_manual'
              : null;
      const source = sourceKey ? i18n.t(sourceKey) : account.source;
      const hint =
        account.status === 'auth'
          ? i18n.s('signInHint', { cmd: account.provider === 'codex' ? 'codex login' : 'grok login' })
          : account.statusHint;
      return h(
        'article',
        { className: 'dsh-um-card' },
        h(
          'div',
          { className: 'dsh-um-card-head' },
          h(
            'div',
            { className: 'dsh-um-ident' },
            h(
              'span',
              { className: 'dsh-um-mono', style: { background: providerColor(account.provider) }, 'aria-hidden': true },
              providerInitial(account.provider),
            ),
            h(
              'div',
              { className: 'dsh-um-ident-text' },
              h('div', { className: 'dsh-um-name', title: account.label }, account.label),
              h(
                'div',
                { className: 'dsh-um-source' },
                [source, account.plan].filter(Boolean).join(' · '),
              ),
            ),
          ),
          h(
            'div',
            { className: 'dsh-um-badges' },
            account.limitReached
              ? h('span', { className: 'dsh-um-chip is-danger' }, i18n.t('exhausted'))
              : null,
            h(
              'span',
              { className: `dsh-um-status is-${status.level}` },
              h('i', { 'aria-hidden': true }),
              h('span', null, status.label),
            ),
          ),
        ),
        (account.windows || []).map((window) =>
          h(WindowRow, { key: window.key, account, window, i18n, now }),
        ),
        h(Extras, { account, i18n }),
        account.status !== 'ok'
          ? h(
              'div',
              { className: 'dsh-um-warn', role: 'note' },
              h('div', null, account.statusDetail || i18n.t('unavailable')),
              hint ? h('div', { className: 'dsh-um-warn-hint' }, hint) : null,
            )
          : null,
      );
    }

    function Skeleton() {
      return h(
        'div',
        { className: 'dsh-um-skeleton-wrap', 'aria-hidden': true },
        [0, 1].map((index) =>
          h(
            'div',
            { className: 'dsh-um-skeleton', key: index },
            h('div', { className: 'dsh-um-skeleton-line w40' }),
            h('div', { className: 'dsh-um-skeleton-line w80' }),
            h('div', { className: 'dsh-um-skeleton-line w60' }),
          ),
        ),
      );
    }

    function Panel({ store, i18n }) {
      const snapshot = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const data = snapshot.data;
      const accounts = data && Array.isArray(data.accounts) ? data.accounts : [];
      const now = snapshot.now;
      const sections = [
        { id: 'codex', label: i18n.t('codex'), accounts: accounts.filter((account) => account.provider === 'codex') },
        { id: 'claude', label: i18n.t('claude'), accounts: accounts.filter((account) => account.provider === 'claude') },
        { id: 'grok', label: i18n.t('grok'), accounts: accounts.filter((account) => account.provider === 'grok') },
        {
          id: 'other',
          label: i18n.t('accounts'),
          accounts: accounts.filter((account) => !['codex', 'claude', 'grok'].includes(account.provider)),
        },
      ].filter((section) => section.accounts.length > 0);
      const updatedAt = data && data.updatedAt ? Date.parse(data.updatedAt) : 0;
      const updatedLabel = updatedAt
        ? now - updatedAt < 60_000
          ? i18n.t('justNow')
          : i18n.s('minutesAgo', { n: Math.max(1, Math.round((now - updatedAt) / 60_000)) })
        : '';

      return h(
        'div',
        { className: 'dsh-um-panel', 'data-usage-monitor': 'panel' },
        h(Styles),
        h(
          'header',
          { className: 'dsh-um-header' },
          h(
            'div',
            null,
            h('h1', { className: 'dsh-um-title' }, i18n.t('panel')),
            h('p', { className: 'dsh-um-subtitle' }, i18n.t('subtitle')),
          ),
          h(
            'div',
            { className: 'dsh-um-toolbar' },
            updatedLabel
              ? h('span', { className: 'dsh-um-updated' }, `${i18n.t('updated')} ${updatedLabel}`)
              : null,
            h(
              'button',
              {
                type: 'button',
                className: `dsh-um-btn${snapshot.refreshing ? ' is-busy' : ''}`,
                onClick: () => store.refresh(),
                disabled: snapshot.refreshing,
              },
              h(RefreshIcon, { size: 14 }),
              h('span', null, i18n.t(snapshot.refreshing ? 'refreshing' : 'refresh')),
            ),
          ),
        ),
        snapshot.error
          ? h(
              'div',
              { className: 'dsh-um-error', role: 'alert' },
              h(
                'div',
                { className: 'dsh-um-error-text' },
                h('strong', null, i18n.t('errorTitle')),
                h('span', null, snapshot.error),
              ),
              h(
                'button',
                { type: 'button', className: 'dsh-um-btn', onClick: () => store.load() },
                i18n.t('retry'),
              ),
            )
          : null,
        snapshot.loading && !data ? h(Skeleton) : null,
        data && !accounts.length
          ? h(
              'div',
              { className: 'dsh-um-empty' },
              h(
                'div',
                { className: 'dsh-um-empty-icon' },
                h(GaugeIcon, { size: 34 }),
              ),
              h('h2', null, i18n.t('emptyTitle')),
              h('p', null, i18n.t('emptyBody')),
              h(
                'div',
                { className: 'dsh-um-cmds' },
                h('code', null, 'codex login'),
                h('code', null, 'grok login'),
              ),
              data.diag && data.diag.discoveryError
                ? h('p', { className: 'dsh-um-empty-error' }, data.diag.discoveryError)
                : null,
            )
          : null,
        sections.map((section) =>
          h(
            'section',
            { className: 'dsh-um-section', key: section.id },
            h(
              'div',
              { className: 'dsh-um-section-head' },
              h('h2', null, section.label),
              h('span', { className: 'dsh-um-count' }, `${section.accounts.length} ${i18n.t('accounts')}`),
            ),
            section.accounts.map((account) =>
              h(AccountCard, {
                key: account.id,
                account,
                i18n,
                now,
                stale: accountStale(account, data, now),
              }),
            ),
          ),
        ),
        h(
          'footer',
          { className: 'dsh-um-footer' },
          h('span', null, i18n.t('privacy')),
          data && data.ui && data.ui.pollSeconds
            ? h('span', null, i18n.s('autoRefresh', { n: data.ui.pollSeconds }))
            : null,
        ),
      );
    }

    function PanelIcon({ size = 20, active, store }) {
      const snapshot = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const data = snapshot.data;
      const accounts = data ? data.accounts || [] : [];
      const level = accounts.some((account) => account.status === 'auth' || account.status === 'error')
        ? 'danger'
        : accounts.some((account) =>
              (account.windows || []).some((window) => clampPercent(window.remainingPercent) <= 10),
            )
          ? 'warn'
          : null;
      return h(
        'svg',
        {
          viewBox: '0 0 24 24',
          width: size,
          height: size,
          fill: 'none',
          'aria-hidden': true,
          className: `dsh-um-gauge${active ? ' is-active' : ''}`,
        },
        h('rect', { x: 3, y: 6, width: 13, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.95 }),
        h('rect', { x: 3, y: 10.5, width: 9.5, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.7 }),
        h('rect', { x: 3, y: 15, width: 6, height: 3, rx: 1.5, fill: 'currentColor', opacity: 0.45 }),
        level
          ? h('circle', {
              cx: 19,
              cy: 5.5,
              r: 2.4,
              fill:
                level === 'danger'
                  ? 'var(--dsw-alias-state-error-primary)'
                  : 'var(--dsw-alias-state-warn-primary)',
            })
          : null,
      );
    }

    function FooterAction({ wide, store, i18n, onOpen }) {
      const snapshot = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const rows = snapshot.data ? worstWindows(snapshot.data.accounts) : [];
      const worst = rows.length ? rows[0] : null;
      const remaining = worst ? Math.round(clampPercent(worst.window.remainingPercent)) : null;
      const level = worst ? levelFor(remaining) : null;
      return h(
        'button',
        {
          type: 'button',
          className: `dsh-um-foot${wide ? '' : ' is-rail'}`,
          onClick: onOpen,
          title: i18n.t('openPanel'),
          'aria-label': i18n.t('panel'),
        },
        h(GaugeIcon, { size: 16 }),
        wide ? h('span', { className: 'dsh-um-foot-label' }, i18n.t('panel')) : null,
        wide && remaining !== null ? h('span', { className: `dsh-um-foot-pct is-${level}` }, `${remaining}%`) : null,
        level ? h('i', { className: `dsh-um-foot-dot is-${level}`, 'aria-hidden': true }) : null,
      );
    }

    function DockStrip({ store, i18n, onOpen }) {
      const snapshot = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const data = snapshot.data;
      if (!data || !data.ui || data.ui.dock === false) return null;
      const rows = worstWindows(data.accounts).slice(0, 3);
      if (!rows.length) return null;
      return h(
        'div',
        { className: 'dsh-um-dock' },
        h(Styles),
        h(
          'button',
          { type: 'button', className: 'dsh-um-dock-main', onClick: onOpen, title: i18n.t('openPanel') },
          h(GaugeIcon, { size: 14 }),
          h('span', null, i18n.t('panel')),
        ),
        h(
          'div',
          { className: 'dsh-um-dock-pills' },
          rows.map(({ account, window }) =>
            h(
              'button',
              {
                type: 'button',
                className: `dsh-um-dock-pill is-${levelFor(clampPercent(window.remainingPercent))}`,
                key: `${account.id}:${window.key}`,
                onClick: onOpen,
                title: `${account.label} · ${windowLabel(window, i18n)} · ${Math.round(
                  clampPercent(window.remainingPercent),
                )}% · ${resetText(window, i18n, snapshot.now)}`,
              },
              h('i', { className: 'dsh-um-dot', 'aria-hidden': true }),
              h('span', null, i18n.t(account.provider)),
              h('b', null, `${Math.round(clampPercent(window.remainingPercent))}%`),
              window.resetsAt
                ? h(
                    'span',
                    { className: 'dsh-um-dock-eta' },
                    durationShort(Math.max(0, Date.parse(window.resetsAt) - snapshot.now)),
                  )
                : null,
            ),
          ),
        ),
      );
    }

    function toastTitle(event, i18n) {
      const name = event.label || i18n.t(event.provider);
      if (event.kind === 'reset') return i18n.s('resetToast', { name });
      if (event.kind === 'refill') return i18n.s('refillToast', { name });
      return i18n.s('lowToast', { name });
    }

    function toastBody(event, i18n) {
      const label = windowLabel({ key: event.windowKey, label: event.windowLabel }, i18n);
      if (event.kind === 'low') {
        return i18n.s('toastLowBody', { window: label, remaining: Math.round(clampPercent(event.remainingPercent)) });
      }
      const key = event.kind === 'reset' ? 'toastResetBody' : 'toastRefillBody';
      return i18n.s(key, {
        window: label,
        from: Math.round(clampPercent(event.fromUsed)),
        to: Math.round(clampPercent(event.toUsed)),
      });
    }

    function Toasts({ store, i18n }) {
      const snapshot = React.useSyncExternalStore(store.subscribe, store.getSnapshot);
      const ids = snapshot.toasts.map((toast) => toast.key).join('|');
      React.useEffect(() => {
        if (!snapshot.toasts.length) return undefined;
        const timers = snapshot.toasts.map((toast) => setTimeout(() => store.dismiss(toast.key), 10_000));
        return () => timers.forEach((timer) => clearTimeout(timer));
      }, [ids]);
      if (!snapshot.toasts.length) return null;
      return h(
        'div',
        { className: 'dsh-um-toasts', 'aria-live': 'polite' },
        h(Styles),
        snapshot.toasts.map((event) =>
          h(
            'div',
            { className: `dsh-um-toast is-${event.kind}`, key: event.key, role: 'status' },
            h(
              'div',
              { className: 'dsh-um-toast-body' },
              h('strong', null, toastTitle(event, i18n)),
              h('span', null, toastBody(event, i18n)),
            ),
            h(
              'button',
              {
                type: 'button',
                className: 'dsh-um-toast-close',
                onClick: () => store.dismiss(event.key),
                'aria-label': i18n.t('dismiss'),
              },
              '×',
            ),
          ),
        ),
      );
    }

    const CSS = `
.dsh-um-panel { max-width: 920px; margin: 0 auto; padding: 30px 34px 72px; color: var(--dsw-alias-label-primary); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang TC", "Microsoft JhengHei", sans-serif; font-size: 13px; line-height: 1.5; }
.dsh-um-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 24px; padding-bottom: 18px; border-bottom: 1px solid var(--dsw-alias-border-l1); }
.dsh-um-title { margin: 0; font-size: 20px; font-weight: 650; letter-spacing: -0.01em; }
.dsh-um-subtitle { margin: 4px 0 0; color: var(--dsw-alias-label-secondary); font-size: 12.5px; }
.dsh-um-toolbar { display: flex; align-items: center; gap: 12px; flex: none; }
.dsh-um-updated { color: var(--dsw-alias-label-secondary); font-size: 12px; white-space: nowrap; }
.dsh-um-btn { display: inline-flex; align-items: center; gap: 6px; height: 30px; padding: 0 11px; border-radius: 8px; border: 1px solid var(--dsw-alias-border-l2); background: var(--dsw-alias-bg-layer-1); color: var(--dsw-alias-label-primary); font: inherit; font-size: 12.5px; cursor: pointer; }
.dsh-um-btn:hover:not([disabled]) { background: var(--dsw-alias-bg-layer-2); }
.dsh-um-btn:focus-visible, .dsh-um-dock-pill:focus-visible, .dsh-um-dock-main:focus-visible, .dsh-um-toast-close:focus-visible { outline: 2px solid var(--dsw-alias-brand-primary); outline-offset: 2px; }
.dsh-um-btn[disabled] { opacity: 0.6; cursor: default; }
.dsh-um-btn.is-busy svg { animation: dsh-um-spin 1s linear infinite; }
.dsh-um-section { margin-top: 26px; }
.dsh-um-section-head { display: flex; align-items: baseline; gap: 8px; margin-bottom: 10px; }
.dsh-um-section-head h2 { margin: 0; font-size: 11.5px; font-weight: 600; letter-spacing: 0.07em; text-transform: uppercase; color: var(--dsw-alias-label-secondary); }
.dsh-um-count { color: var(--dsw-alias-label-secondary); font-size: 11.5px; }
.dsh-um-card { border: 1px solid var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-1); border-radius: 12px; padding: 14px 16px 13px; margin-bottom: 10px; }
.dsh-um-card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.dsh-um-ident { display: flex; align-items: center; gap: 10px; min-width: 0; }
.dsh-um-mono { width: 28px; height: 28px; border-radius: 8px; display: inline-flex; align-items: center; justify-content: center; color: #fff; font-size: 12px; font-weight: 700; flex: none; }
.dsh-um-ident-text { min-width: 0; }
.dsh-um-name { font-size: 13.5px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dsh-um-source { font-size: 11.5px; color: var(--dsw-alias-label-secondary); }
.dsh-um-badges { display: flex; align-items: center; gap: 8px; flex: none; }
.dsh-um-chip { font-size: 10.5px; font-weight: 600; padding: 2px 7px; border-radius: 999px; border: 1px solid var(--dsw-alias-border-l2); color: var(--dsw-alias-label-secondary); }
.dsh-um-chip.is-danger { color: var(--dsw-alias-state-error-primary); border-color: var(--dsw-alias-state-error-primary); }
.dsh-um-status { display: inline-flex; align-items: center; gap: 5px; font-size: 11.5px; color: var(--dsw-alias-label-secondary); white-space: nowrap; }
.dsh-um-status i { width: 6px; height: 6px; border-radius: 50%; background: var(--dsw-alias-state-success-primary); }
.dsh-um-status.is-warn i { background: var(--dsw-alias-state-warn-primary); }
.dsh-um-status.is-danger i { background: var(--dsw-alias-state-error-primary); }
.dsh-um-window { margin-top: 14px; }
.dsh-um-window-head { display: flex; align-items: baseline; gap: 8px; }
.dsh-um-window-label { min-width: 62px; color: var(--dsw-alias-label-secondary); font-size: 12px; }
.dsh-um-window-value { font-size: 15px; font-weight: 650; letter-spacing: -0.01em; }
.dsh-um-window-used { margin-left: auto; color: var(--dsw-alias-label-secondary); font-size: 11.5px; }
.dsh-um-bar { height: 6px; margin-top: 6px; border-radius: 999px; background: var(--dsw-alias-bg-layer-2); overflow: hidden; }
.dsh-um-bar-fill { height: 100%; border-radius: 999px; background: var(--dsw-alias-brand-primary); transition: width 0.35s ease; }
.dsh-um-bar-fill.is-warn { background: var(--dsw-alias-state-warn-primary); }
.dsh-um-bar-fill.is-danger { background: var(--dsw-alias-state-error-primary); }
.dsh-um-window-meta { margin-top: 5px; color: var(--dsw-alias-label-secondary); font-size: 11.5px; }
.dsh-um-extras { margin-top: 10px; display: flex; flex-wrap: wrap; gap: 8px 14px; }
.dsh-um-products { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
.dsh-um-extras-label { color: var(--dsw-alias-label-secondary); font-size: 11px; }
.dsh-um-product { display: inline-flex; gap: 6px; align-items: baseline; padding: 2px 8px; border-radius: 999px; border: 1px solid var(--dsw-alias-border-l1); font-size: 11px; color: var(--dsw-alias-label-secondary); }
.dsh-um-product b { color: var(--dsw-alias-label-primary); font-weight: 600; }
.dsh-um-extra { display: inline-flex; align-items: baseline; gap: 6px; font-size: 11.5px; color: var(--dsw-alias-label-secondary); }
.dsh-um-extra strong { color: var(--dsw-alias-label-primary); font-weight: 600; }
.dsh-um-extra.is-warning strong { color: var(--dsw-alias-state-warn-primary); }
.dsh-um-warn { margin-top: 10px; padding: 8px 10px; border: 1px solid var(--dsw-alias-state-warn-primary); border-radius: 8px; font-size: 11.5px; }
.dsh-um-warn-hint { margin-top: 3px; color: var(--dsw-alias-label-secondary); }
.dsh-um-error { display: flex; align-items: center; gap: 14px; margin-top: 16px; padding: 12px 14px; border: 1px solid var(--dsw-alias-state-error-primary); border-radius: 10px; background: var(--dsw-alias-bg-layer-1); }
.dsh-um-error-text { display: flex; flex-direction: column; gap: 2px; flex: 1; font-size: 12px; }
.dsh-um-error-text span { color: var(--dsw-alias-label-secondary); }
.dsh-um-empty { margin-top: 24px; padding: 58px 24px; border: 1px dashed var(--dsw-alias-border-l2); border-radius: 14px; text-align: center; }
.dsh-um-empty-icon { color: var(--dsw-alias-label-secondary); display: flex; justify-content: center; margin-bottom: 12px; }
.dsh-um-empty h2 { margin: 0 0 6px; font-size: 15px; font-weight: 600; }
.dsh-um-empty p { margin: 0 auto; max-width: 440px; color: var(--dsw-alias-label-secondary); font-size: 12.5px; }
.dsh-um-cmds { display: flex; justify-content: center; gap: 8px; margin-top: 14px; }
.dsh-um-cmds code { padding: 4px 9px; border-radius: 6px; border: 1px solid var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-2); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11.5px; }
.dsh-um-empty-error { margin-top: 12px !important; color: var(--dsw-alias-state-error-primary) !important; font-size: 11.5px !important; }
.dsh-um-footer { display: flex; justify-content: space-between; gap: 18px; margin-top: 26px; padding-top: 14px; border-top: 1px solid var(--dsw-alias-border-l1); color: var(--dsw-alias-label-secondary); font-size: 11px; }
.dsh-um-skeleton-wrap { display: flex; flex-direction: column; gap: 10px; margin-top: 24px; }
.dsh-um-skeleton { border: 1px solid var(--dsw-alias-border-l1); border-radius: 12px; padding: 16px; background: var(--dsw-alias-bg-layer-1); }
.dsh-um-skeleton-line { height: 10px; border-radius: 999px; background: var(--dsw-alias-bg-layer-2); margin-bottom: 9px; }
.dsh-um-skeleton-line.w40 { width: 40%; }
.dsh-um-skeleton-line.w80 { width: 80%; }
.dsh-um-skeleton-line.w60 { width: 60%; margin-bottom: 0; }
.dsh-um-gauge { display: block; flex: none; }
.dsh-um-foot { display: flex; align-items: center; gap: 7px; width: 100%; height: 28px; padding: 0 8px; border: 0; border-radius: 6px; background: transparent; color: var(--dsw-alias-label-secondary); font: inherit; font-size: 12px; cursor: pointer; text-align: left; }
.dsh-um-foot:hover { background: var(--dsw-alias-bg-layer-1); color: var(--dsw-alias-label-primary); }
.dsh-um-foot:focus-visible { outline: 2px solid var(--dsw-alias-brand-primary); outline-offset: 2px; }
.dsh-um-foot.is-rail { justify-content: center; padding: 0; }
.dsh-um-foot-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dsh-um-foot-pct { margin-left: auto; font-size: 11px; font-variant-numeric: tabular-nums; color: var(--dsw-alias-label-secondary); }
.dsh-um-foot-pct.is-warn, .dsh-um-foot-pct.is-danger { color: var(--dsw-alias-state-warn-primary); }
.dsh-um-foot-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--dsw-alias-state-warn-primary); flex: none; }
.dsh-um-foot-dot.is-danger { background: var(--dsw-alias-state-error-primary); }
.dsh-um-dock { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 2px 2px 0; }
.dsh-um-dock-main { display: inline-flex; align-items: center; gap: 6px; height: 24px; padding: 0 8px; border: 1px solid transparent; border-radius: 999px; background: transparent; color: var(--dsw-alias-label-secondary); font: inherit; font-size: 11.5px; cursor: pointer; }
.dsh-um-dock-main:hover { color: var(--dsw-alias-label-primary); background: var(--dsw-alias-bg-layer-1); }
.dsh-um-dock-pills { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.dsh-um-dock-pill { display: inline-flex; align-items: center; gap: 6px; height: 24px; padding: 0 9px; border-radius: 999px; border: 1px solid var(--dsw-alias-border-l1); background: var(--dsw-alias-bg-layer-1); color: var(--dsw-alias-label-secondary); font: inherit; font-size: 11.5px; cursor: pointer; }
.dsh-um-dock-pill:hover { border-color: var(--dsw-alias-border-l2); color: var(--dsw-alias-label-primary); }
.dsh-um-dock-pill b { color: var(--dsw-alias-label-primary); font-weight: 600; }
.dsh-um-dock-pill.is-warn .dsh-um-dot { background: var(--dsw-alias-state-warn-primary); }
.dsh-um-dock-pill.is-danger .dsh-um-dot { background: var(--dsw-alias-state-error-primary); }
.dsh-um-dock-eta { color: var(--dsw-alias-label-secondary); font-variant-numeric: tabular-nums; }
.dsh-um-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--dsw-alias-state-success-primary); }
.dsh-um-toasts { position: fixed; right: 20px; bottom: 20px; z-index: 60; display: flex; flex-direction: column; gap: 8px; width: min(360px, calc(100vw - 32px)); pointer-events: none; }
.dsh-um-toast { pointer-events: auto; display: flex; align-items: flex-start; gap: 10px; padding: 11px 12px; border: 1px solid var(--dsw-alias-border-l2); border-left-width: 3px; border-radius: 10px; background: var(--dsw-alias-bg-overlay); box-shadow: 0 10px 28px rgba(0, 0, 0, 0.2); }
.dsh-um-toast.is-reset { border-left-color: var(--dsw-alias-state-success-primary); }
.dsh-um-toast.is-refill { border-left-color: var(--dsw-alias-brand-primary); }
.dsh-um-toast.is-low { border-left-color: var(--dsw-alias-state-warn-primary); }
.dsh-um-toast-body { display: flex; flex-direction: column; gap: 2px; flex: 1; font-size: 12px; }
.dsh-um-toast-body strong { font-size: 12.5px; font-weight: 600; }
.dsh-um-toast-body span { color: var(--dsw-alias-label-secondary); }
.dsh-um-toast-close { border: 0; background: transparent; color: var(--dsw-alias-label-secondary); font-size: 16px; line-height: 1; padding: 0 2px; cursor: pointer; }
@keyframes dsh-um-spin { from { transform: rotate(0); } to { transform: rotate(360deg); } }
@media (max-width: 760px) {
  .dsh-um-panel { padding: 20px 16px 56px; }
  .dsh-um-header { flex-direction: column; gap: 12px; }
  .dsh-um-toolbar { width: 100%; justify-content: space-between; }
  .dsh-um-footer { flex-direction: column; gap: 6px; }
}
@media (prefers-reduced-motion: reduce) {
  .dsh-um-bar-fill, .dsh-um-toast { transition: none; }
  .dsh-um-btn.is-busy svg { animation: none; }
}
`;

    function apply(ctx) {
      ctx.effect(() => {
        const en = ctx.locale.register(NS, 'en', EN);
        const zh = ctx.locale.register(NS, 'zh', ZH);
        return () => {
          zh();
          en();
        };
      }, 'usage-monitor: locale dictionaries');

      const bound = ctx.locale.bind(NS);
      const translate = (key) => {
        let value;
        try {
          value = bound(key);
        } catch {
          value = key;
        }
        return value && value !== key ? value : EN[key] || key;
      };
      const i18n = {
        t: translate,
        s: (key, vars) => fill(translate(key), vars),
        zh: () => {
          try {
            return String(ctx.locale.getLocale().active || 'en').toLowerCase().startsWith('zh');
          } catch {
            return false;
          }
        },
      };

      const store = createStore(ctx);
      ctx.effect(() => store.start(), 'usage-monitor: poller');
      ctx.effect(() => ctx.locale.subscribe(() => store.bumpLocale()), 'usage-monitor: locale subscription');

      const openPanel = () => {
        try {
          const layout = ctx.get('layout');
          if (layout && typeof layout.selectPanel === 'function') layout.selectPanel(PANEL_ID);
        } catch {
          // navigation is a convenience; the panel still renders when selected
        }
      };

      ctx.slots.inject('main', () =>
        ctx.slots.register(
          { name: 'main', key: PANEL_ID, locale: NS, inject: () => ({ store, i18n }) },
          Panel,
        ),
      );

      ctx.slots.inject('sidebar.panellist', () =>
        ctx.slots.register(
          {
            name: 'sidebar.panellist',
            id: PANEL_ID,
            order: 20,
            locale: NS,
            label: () => translate('panel'),
            inject: () => ({ store }),
          },
          PanelIcon,
        ),
      );

      ctx.slots.inject('sidebar.footer.action', () =>
        ctx.slots.register(
          {
            name: 'sidebar.footer.action',
            id: 'usage-monitor-footer',
            order: 20,
            locale: NS,
            label: () => translate('panel'),
            inject: () => ({ store, i18n, onOpen: openPanel }),
          },
          FooterAction,
        ),
      );

      ctx.slots.inject('conversation.composer.dock', () =>
        ctx.slots.register(
          {
            name: 'conversation.composer.dock',
            id: 'usage-monitor',
            order: 6,
            locale: NS,
            inject: () => ({ store, i18n, onOpen: openPanel }),
          },
          DockStrip,
        ),
      );

      ctx.slots.inject('shell.overlay', () =>
        ctx.slots.register(
          {
            name: 'shell.overlay',
            id: 'usage-monitor-toasts',
            order: 100,
            locale: NS,
            inject: () => ({ store, i18n }),
          },
          Toasts,
        ),
      );

      return { store };
    }

    return { inject: ['slots', 'locale'], apply };
  },
});
