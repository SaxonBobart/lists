/* Lists — Home-screen alternates (dark)
 * 8 different ways to organize Smart Lists, My Lists, and Agents.
 * Each component renders the inside of a phone (Phone wrapper applied at canvas).
 */

// Shared chrome — large title + toolbar (Search, More)
const HomeChrome = ({ title = 'Lists', sub, sticky }) => (
  <div style={{ padding: '6px 16px 8px', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
    <div>
      {sub && <div style={{ fontSize: 12, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, fontWeight: 600, marginBottom: 2 }}>{sub}</div>}
      <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>{title}</div>
    </div>
    <div style={{ display: 'flex', gap: 6 }}>
      <CircleBtn icon="search" />
      <CircleBtn icon="moreH" />
    </div>
  </div>
);

const SectionLabel = ({ label, action = '+', divider = true }) => (
  <>
    {divider && <div style={{ height: 0.5, background: 'var(--sep-translucent)', margin: '14px 16px 0' }} />}
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px 6px' }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--fg-secondary)' }}>{label}</div>
      {action && <Icon name={action === '+' ? 'plus' : action} s={16} color="var(--accent)" strokeWidth={2.1} />}
    </div>
  </>
);

const RootCol = ({ children }) => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>{children}</div>
);

// Common smart-list data, varied by surface
const SMARTS = [
  { icon: 'sun', hue: 'var(--hue-amber)', label: 'Today', count: 7, active: true },
  { icon: 'calendar', hue: 'var(--hue-orange)', label: 'Scheduled', count: 24 },
  { icon: 'flag', hue: 'var(--hue-pink)', label: 'Flagged', count: 3 },
  { icon: 'bolt', hue: 'var(--danger)', label: 'Urgent', count: 1 },
  { icon: 'check', hue: 'var(--hue-grey)', label: 'Completed', count: 112, hideCount: true },
  { icon: 'inbox', hue: 'var(--accent)', label: 'All', count: 148 },
];
const LISTS = [
  { icon: 'list', hue: 'var(--hue-blue)', label: 'Tasks', count: 12 },
  { icon: 'folder', hue: 'var(--hue-amber)', label: 'Work', count: 8, kids: [
    { icon: 'sparkle1', hue: 'var(--accent)', label: 'Project Apollo', count: 5 },
    { icon: 'book', hue: 'var(--hue-purple)', label: 'Reading', count: 3 },
  ]},
  { icon: 'home', hue: 'var(--hue-pink)', label: 'Personal', count: 4 },
  { icon: 'cart', hue: 'var(--hue-green)', label: 'Groceries', count: 11, presence: true },
  { icon: 'leaf', hue: 'var(--hue-teal)', label: 'Habits', count: 6 },
];
const AGENTS = [
  { icon: 'cpu', hue: 'var(--hue-purple)', label: 'Claude Code', count: 2, agent: 'working' },
  { icon: 'cpu', hue: 'var(--hue-blue)', label: 'opencode', count: 0, agent: 'idle' },
];

// Filled smart card — variant for SidebarA: bg = icon hue, icon top-left,
// count top-right, label bottom-left.
const SmartCardFilled = ({ icon, hue, label, count, active, hideCount }) => (
  <div style={{
    background: hue, color: '#fff',
    borderRadius: 14, padding: 14,
    minHeight: 92, position: 'relative',
    display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
    boxShadow: active ? '0 0 0 2px var(--accent) inset, 0 0 0 4px var(--bg-grouped) inset' : 'none',
  }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
      <Icon name={icon} s={22} color="#fff" strokeWidth={2.1} />
      {!hideCount && (
        <span className="mono" style={{
          fontSize: 26, fontWeight: 700, lineHeight: 1, letterSpacing: -0.4, color: '#fff',
        }}>{count}</span>
      )}
    </div>
    <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.1, color: '#fff' }}>
      {label}
    </div>
  </div>
);

// ── A · Reminders-classic — refined grid + flat lists ─────────
const SidebarA = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <div style={{ padding: '0 16px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {SMARTS.map(s => <SmartCardFilled key={s.label} {...s} />)}
        </div>
      </div>
      <SectionLabel label="My Lists" divider={false} />
      {LISTS.map((l, i) => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
      <SectionLabel label="System" />
      <SidebarRow icon="tag" hue="var(--hue-grey)" label="Tags" count={14} />
      <SidebarRow icon="trash" hue="var(--hue-grey)" label="Recently Deleted" count={6} />
    </div>
  </RootCol>
);

// Filled smart row — full-width colored bar variant for SidebarB.
const SmartRowFilled = ({ icon, hue, label, count, active, hideCount }) => (
  <div style={{
    background: hue, color: '#fff',
    margin: '0 16px 8px', borderRadius: 12,
    padding: '12px 14px', minHeight: 52,
    display: 'flex', alignItems: 'center', gap: 12,
    boxShadow: active ? '0 0 0 2px var(--accent) inset, 0 0 0 4px var(--bg-grouped) inset' : 'none',
  }}>
    <Icon name={icon} s={19} color="#fff" strokeWidth={2.1} />
    <div style={{ flex: 1, fontSize: 15, fontWeight: 700, letterSpacing: -0.1 }}>{label}</div>
    {!hideCount && (
      <span className="mono" style={{ fontSize: 18, fontWeight: 700, lineHeight: 1, letterSpacing: -0.3, color: '#fff' }}>{count}</span>
    )}
  </div>
);

// ── B · Compact rows — filled Favorite rows + dense list rows below ──
const SidebarB = () => (
  <RootCol>
    <HomeChrome title="Lists" sub="35 lists · 148 items" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <SectionLabel label="Favorites" divider={false} action={null} />
      {SMARTS.map(s => <SmartRowFilled key={s.label} {...s} />)}
      <SectionLabel label="My Lists" />
      {LISTS.map(l => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
      <SectionLabel label="System" />
      <SidebarRow icon="tag" hue="var(--hue-grey)" label="Tags" count={14} />
      <SidebarRow icon="trash" hue="var(--hue-grey)" label="Recently Deleted" count={6} />
    </div>
  </RootCol>
);

// ── C · Today-hero — Today is huge, others are chips ──────────
const SidebarC = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <div style={{ padding: '0 16px' }}>
        <div style={{
          background: 'var(--accent-soft)', borderRadius: 16, padding: 16,
          display: 'flex', flexDirection: 'column', gap: 6,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div style={{ width: 36, height: 36, borderRadius: 18, background: 'var(--hue-amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="sun" s={20} color="#fff" strokeWidth={2}/>
              </div>
              <div>
                <div style={{ fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, fontWeight: 600 }}>Friday, May 8</div>
                <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.3 }}>Today</div>
              </div>
            </div>
            <div className="mono" style={{ fontSize: 30, fontWeight: 700, color: 'var(--accent-tint-fg)', lineHeight: 1 }}>7</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4, color: 'var(--fg-secondary)', fontSize: 13 }}>
            <span>2 overdue</span><span>·</span><span>3 morning</span><span>·</span><span>2 afternoon</span>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 8, padding: '10px 16px 0', overflowX: 'auto', flexWrap: 'wrap' }}>
        {SMARTS.slice(1).map(s => (
          <div key={s.label} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '7px 11px', borderRadius: 999,
            background: 'var(--bg-elevated)',
          }}>
            <Icon name={s.icon} s={13} color={s.hue} strokeWidth={2.2} />
            <span style={{ fontSize: 13, fontWeight: 500, color: 'var(--fg-primary)' }}>{s.label}</span>
            <span className="mono" style={{ fontSize: 11, color: 'var(--fg-tertiary)' }}>{s.count}</span>
          </div>
        ))}
      </div>

      <SectionLabel label="My Lists" />
      {LISTS.map(l => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
    </div>
  </RootCol>
);

// ── D · Horizontal carousel ───────────────────────────────────
const SidebarD = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <div style={{ display: 'flex', gap: 10, padding: '0 16px 6px', overflowX: 'auto', scrollSnapType: 'x mandatory' }}>
        {SMARTS.map(s => (
          <div key={s.label} style={{
            flex: '0 0 auto', width: 130, scrollSnapAlign: 'start',
            background: s.active ? 'var(--accent-soft)' : 'var(--bg-elevated)',
            borderRadius: 14, padding: 12, display: 'flex', flexDirection: 'column', gap: 8,
            minHeight: 110,
          }}>
            <div style={{ width: 28, height: 28, borderRadius: 14, background: s.hue, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name={s.icon} s={15} color="#fff" strokeWidth={2.1}/>
            </div>
            <div style={{ marginTop: 'auto' }}>
              <div className="mono" style={{ fontSize: 24, fontWeight: 700, color: s.active ? 'var(--accent-tint-fg)' : 'var(--fg-primary)', lineHeight: 1 }}>{s.count}</div>
              <div style={{ fontSize: 13, fontWeight: 600, color: s.active ? 'var(--accent-tint-fg)' : 'var(--fg-secondary)', marginTop: 4 }}>{s.label}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', justifyContent: 'center', gap: 4, padding: '8px 0 4px' }}>
        {[0,1,2,3].map(i => (
          <div key={i} style={{ width: 5, height: 5, borderRadius: 5, background: i === 0 ? 'var(--accent)' : 'var(--fg-tertiary)', opacity: i === 0 ? 1 : 0.4 }} />
        ))}
      </div>
      <SectionLabel label="My Lists" />
      {LISTS.map(l => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
    </div>
  </RootCol>
);

// ── E · Customizable Pinned (mix of smart, list, tag) ─────────
const SidebarE = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <SectionLabel label="Favorites" divider={false} action="sliders" />
      <div style={{ padding: '0 16px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <SmartCard icon="sun" hue="var(--hue-amber)" label="Today" count={7} active />
          <SmartCard icon="cart" hue="var(--hue-green)" label="Groceries" count={11} />
          <SmartCard icon="bolt" hue="var(--danger)" label="Urgent" count={1} />
          <SmartCard icon="sparkle1" hue="var(--accent)" label="Apollo" count={5} />
          <div style={{
            background: 'var(--bg-elevated)', borderRadius: 14, padding: 12,
            display: 'flex', flexDirection: 'column', gap: 4, minHeight: 86,
            justifyContent: 'space-between',
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <div style={{ width: 30, height: 30, borderRadius: 15, background: 'var(--hue-grey)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="tag" s={15} color="#fff" strokeWidth={2.1}/>
              </div>
              <span className="mono" style={{ fontSize: 22, fontWeight: 700, color: 'var(--fg-primary)', lineHeight: 1 }}>9</span>
            </div>
            <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--fg-secondary)', fontFamily: 'var(--font-mono)' }}>#errand</div>
          </div>
          <div style={{
            background: 'var(--bg-elevated)', borderRadius: 14, padding: 12,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: 'var(--fg-tertiary)', minHeight: 86, gap: 6,
            border: '1.5px dashed var(--sep-opaque)',
          }}>
            <Icon name="plus" s={16} color="var(--fg-tertiary)" strokeWidth={2}/>
            <span style={{ fontSize: 12, fontWeight: 500 }}>Pin a list</span>
          </div>
        </div>
      </div>
      <SectionLabel label="All Smart Lists" />
      {SMARTS.filter(s => !['Today'].includes(s.label)).map(s => <SidebarRow key={s.label} {...s} />)}
      <SectionLabel label="My Lists" />
      {LISTS.map(l => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
    </div>
  </RootCol>
);

// ── F · Sectioned by purpose (Time / Planning / Reference / Agents) ─
const SidebarF = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <SectionLabel label="Time" divider={false} />
      <SidebarRow icon="sun" hue="var(--hue-amber)" label="Today" count={7} active />
      <SidebarRow icon="calendar" hue="var(--hue-orange)" label="Scheduled" count={24} />
      <SidebarRow icon="bolt" hue="var(--danger)" label="Urgent" count={1} />
      <SectionLabel label="Lists" />
      <SidebarRow icon="list" hue="var(--hue-blue)" label="Tasks" count={12} />
      <SidebarRow icon="folder" hue="var(--hue-amber)" label="Work" count={8} />
      <SidebarRow icon="sparkle1" hue="var(--accent)" label="Project Apollo" count={5} indent={1} />
      <SidebarRow icon="book" hue="var(--hue-purple)" label="Reading" count={3} indent={1} />
      <SidebarRow icon="home" hue="var(--hue-pink)" label="Personal" count={4} />
      <SidebarRow icon="cart" hue="var(--hue-green)" label="Groceries" count={11} presence />
      <SidebarRow icon="leaf" hue="var(--hue-teal)" label="Habits" count={6} />
      <SectionLabel label="Reference" />
      <SidebarRow icon="tag" hue="var(--hue-grey)" label="Tags" count={14} />
      <SidebarRow icon="flag" hue="var(--hue-pink)" label="Flagged" count={3} />
      <SidebarRow icon="check" hue="var(--hue-grey)" label="Completed" count={112} />
      <SidebarRow icon="inbox" hue="var(--accent)" label="All" count={148} />
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
      <SectionLabel label="Trash" />
      <SidebarRow icon="trash" hue="var(--hue-grey)" label="Recently Deleted" count={6} />
    </div>
  </RootCol>
);

// ── G · Color-rail (Tot-flavored) — colored bars per list ─────
const SidebarG = () => {
  const Bar = ({ hue, icon, label, count, large, indent = 0, presence, agent }) => (
    <div style={{
      margin: '0 16px 6px', marginLeft: 16 + indent * 16,
      borderRadius: 12, overflow: 'hidden',
      background: 'var(--bg-elevated)',
      display: 'flex', alignItems: 'stretch',
      minHeight: large ? 64 : 44,
      boxShadow: '0 1px 0 var(--sep-opaque) inset',
    }}>
      <div style={{ width: 5, background: hue }} />
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px' }}>
        <Icon name={icon} s={18} color={hue} strokeWidth={2}/>
        <div style={{ flex: 1, fontSize: large ? 17 : 15, fontWeight: large ? 700 : 500, color: 'var(--fg-primary)', letterSpacing: large ? -0.2 : 0 }}>{label}</div>
        {presence && <div style={{ width: 7, height: 7, borderRadius: 7, background: 'var(--accent)' }} />}
        {agent && <span className="mono" style={{ fontSize: 10, color: 'var(--accent-tint-fg)', fontWeight: 600 }}>{agent}</span>}
        <span className="mono" style={{ fontSize: large ? 18 : 13, fontWeight: 600, color: 'var(--fg-tertiary)' }}>{count}</span>
      </div>
    </div>
  );
  return (
    <RootCol>
      <HomeChrome title="Lists" />
      <div style={{ flex: 1, overflow: 'auto', padding: '6px 0 24px' }}>
        <SectionLabel label="Favorites" divider={false} />
        {SMARTS.slice(0, 4).map(s => <Bar key={s.label} {...s} large={s.label === 'Today'} />)}
        <SectionLabel label="My Lists" />
        {LISTS.map(l => (
          <React.Fragment key={l.label}>
            <Bar {...l} />
            {l.kids && l.kids.map(k => <Bar key={k.label} {...k} indent={1} />)}
          </React.Fragment>
        ))}
        <SectionLabel label="Agents" />
        {AGENTS.map(a => <Bar key={a.label} {...a} />)}
      </div>
    </RootCol>
  );
};

// ── H · Widget Today — Today shows 3 next items inline ─────────
const SidebarH = () => (
  <RootCol>
    <HomeChrome title="Lists" />
    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0 24px' }}>
      <div style={{ padding: '0 16px' }}>
        <div style={{
          background: 'var(--bg-elevated)', borderRadius: 16, padding: 14,
          display: 'flex', flexDirection: 'column', gap: 10,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <div style={{ width: 28, height: 28, borderRadius: 14, background: 'var(--hue-amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="sun" s={15} color="#fff" strokeWidth={2.2}/>
              </div>
              <div style={{ fontSize: 17, fontWeight: 700, color: 'var(--fg-primary)' }}>Today</div>
              <span className="mono" style={{ fontSize: 13, fontWeight: 500, color: 'var(--fg-tertiary)' }}>7</span>
            </div>
            <Icon name="chevronR" s={14} color="var(--fg-tertiary)"/>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[
              { time: '9:00', title: 'Standup w/ agentic crew', overdue: false },
              { time: '2:30', title: 'Pick up dry cleaning', overdue: false },
              { time: '5:00', title: 'Call Mum', flag: true },
            ].map((it, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 0' }}>
                <Checkbox />
                <span className="mono" style={{ fontSize: 12, color: 'var(--accent-tint-fg)', fontWeight: 600, minWidth: 36 }}>{it.time}</span>
                <span style={{ flex: 1, fontSize: 14, color: 'var(--fg-primary)' }}>{it.title}</span>
                {it.flag && <Icon name="flagFill" s={12} color="var(--warn)"/>}
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8, padding: '12px 16px 0', flexWrap: 'wrap' }}>
        {SMARTS.slice(1).map(s => (
          <div key={s.label} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '6px 10px', borderRadius: 999,
            background: 'var(--bg-elevated)',
          }}>
            <Icon name={s.icon} s={12} color={s.hue} strokeWidth={2.2}/>
            <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--fg-primary)' }}>{s.label}</span>
            <span className="mono" style={{ fontSize: 11, color: 'var(--fg-tertiary)' }}>{s.count}</span>
          </div>
        ))}
      </div>
      <SectionLabel label="My Lists" />
      {LISTS.map(l => (
        <React.Fragment key={l.label}>
          <SidebarRow {...l} />
          {l.kids && l.kids.map(k => <SidebarRow key={k.label} {...k} indent={1} />)}
        </React.Fragment>
      ))}
      <SectionLabel label="Agents" />
      {AGENTS.map(a => <SidebarRow key={a.label} {...a} />)}
    </div>
  </RootCol>
);

Object.assign(window, { SidebarA, SidebarB, SidebarC, SidebarD, SidebarE, SidebarF, SidebarG, SidebarH });
