/* Lists — UI primitives shared across screens
 * Components: Icon, Checkbox, ListRow, SectionHead, Pill, IconBadge,
 *             SidebarRow, FAB, Stack, Sheet, Heatmap pieces.
 *
 * All components consume CSS custom properties from tokens.css.
 * Pass a `theme` prop ('light'|'dark'|'oled') only at the artboard root —
 * inner components inherit.
 */

// ── Icons ───────────────────────────────────────────────────────
// Hand-rolled minimal stroke icons (SF-Symbols-adjacent). Sized via `s` prop.
const Icon = ({ name, s = 18, color = 'currentColor', strokeWidth = 1.7, ...rest }) => {
  const p = { fill: 'none', stroke: color, strokeWidth, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const f = { fill: color, stroke: 'none' };
  const paths = {
    // Status / smartlist
    sun:        <g {...p}><circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"/></g>,
    calendar:   <g {...p}><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/></g>,
    inbox:      <g {...p}><path d="M3 13l2.5-7A2 2 0 017.4 4.6h9.2A2 2 0 0118.5 6L21 13v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5z"/><path d="M3 13h5l1 2h6l1-2h5"/></g>,
    flag:       <g {...p}><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></g>,
    flagFill:   <g><path d="M5 21V4" {...p}/><path d="M5 4h11l-2 4 2 4H5z" {...f}/></g>,
    bolt:       <g {...p}><path d="M13 3L4 14h7l-1 7 9-11h-7l1-7z"/></g>,
    check:      <g {...p}><path d="M5 12l5 5 9-11"/></g>,
    checkBold:  <g {...p} strokeWidth={2.4}><path d="M5 12.5l4.5 4.5L19 7.5"/></g>,
    plus:       <g {...p} strokeWidth={2}><path d="M12 5v14M5 12h14"/></g>,
    plusBold:   <g {...p} strokeWidth={2.4}><path d="M12 5v14M5 12h14"/></g>,
    chevronR:   <g {...p}><path d="M9 5l7 7-7 7"/></g>,
    chevronD:   <g {...p}><path d="M5 9l7 7 7-7"/></g>,
    bell:       <g {...p}><path d="M6 17V11a6 6 0 0112 0v6l1.5 2H4.5L6 17zM10 21a2 2 0 004 0"/></g>,
    bellSlash:  <g {...p}><path d="M6 17V11a6 6 0 0110.5-3.9M18 11v6l1.5 2H7M10 21a2 2 0 004 0M3 3l18 18"/></g>,
    repeat:     <g {...p}><path d="M4 9V7a3 3 0 013-3h11l-3-3M3 12l3 3M20 15v2a3 3 0 01-3 3H6l3 3"/></g>,
    pin:        <g {...p}><path d="M14 4l6 6-4 1-3 3 1 3-1 1-7-7 1-1 3 1 3-3 1-4z"/></g>,
    tag:        <g {...p}><path d="M3 12V4h8l10 10-8 8L3 12z"/><circle cx="8" cy="9" r="1.5"/></g>,
    trash:      <g {...p}><path d="M4 7h16M9 7V4h6v3M6 7l1 13a2 2 0 002 2h6a2 2 0 002-2l1-13M10 11v7M14 11v7"/></g>,
    list:       <g {...p}><path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4.5" cy="6" r="1.2" {...f}/><circle cx="4.5" cy="12" r="1.2" {...f}/><circle cx="4.5" cy="18" r="1.2" {...f}/></g>,
    folder:     <g {...p}><path d="M3 6a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V6z"/></g>,
    cart:       <g {...p}><path d="M3 5h2l2.5 11a1.5 1.5 0 001.5 1.2h8.4a1.5 1.5 0 001.5-1.2L20.5 8H6.5"/><circle cx="10" cy="20.5" r="1.2"/><circle cx="17" cy="20.5" r="1.2"/></g>,
    leaf:       <g {...p}><path d="M5 19c8-1 14-7 14-15-7 0-13 6-14 14M5 19c1-3 3-6 6-8"/></g>,
    book:       <g {...p}><path d="M4 5a2 2 0 012-2h12v18H6a2 2 0 01-2-2V5z"/><path d="M4 17a2 2 0 012-2h12"/></g>,
    code:       <g {...p}><path d="M9 8l-4 4 4 4M15 8l4 4-4 4M13 5l-2 14"/></g>,
    sparkles:   <g {...p}><path d="M5 12l1.5-3L8 12l3 1.5-3 1.5L6.5 18 5 15l-3-1.5L5 12zM16 4l1 2 2 1-2 1-1 2-1-2-2-1 2-1 1-2zM18 14l.7 1.3L20 16l-1.3.7L18 18l-.7-1.3L16 16l1.3-.7L18 14z"/></g>,
    sparkle1:   <g {...p}><path d="M12 3l1.8 5.7L19 11l-5.2 2.3L12 19l-1.8-5.7L5 11l5.2-2.3L12 3z"/></g>,
    location:   <g {...p}><path d="M12 22s7-7 7-13a7 7 0 10-14 0c0 6 7 13 7 13z"/><circle cx="12" cy="9" r="2.5"/></g>,
    clock:      <g {...p}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></g>,
    search:     <g {...p}><circle cx="11" cy="11" r="7"/><path d="M16 16l4 4"/></g>,
    sliders:    <g {...p}><path d="M4 7h11M19 7h1M4 12h1M9 12h11M4 17h15M21 17h-1"/><circle cx="17" cy="7" r="2"/><circle cx="7" cy="12" r="2"/><circle cx="22" cy="17" r="2" transform="translate(-1 0)"/></g>,
    moreH:      <g {...f}><circle cx="6" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="18" cy="12" r="1.6"/></g>,
    grip:       <g {...f}><circle cx="9" cy="6" r="1.3"/><circle cx="15" cy="6" r="1.3"/><circle cx="9" cy="12" r="1.3"/><circle cx="15" cy="12" r="1.3"/><circle cx="9" cy="18" r="1.3"/><circle cx="15" cy="18" r="1.3"/></g>,
    siri:       <g {...p}><path d="M5 12c0-4 3-7 7-7s7 3 7 7M7 12v3M11 9v6M15 7v8M19 12v3"/></g>,
    cpu:        <g {...p}><rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9" y="9" width="6" height="6" rx="1"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/></g>,
    home:       <g {...p}><path d="M4 11l8-7 8 7v9a1 1 0 01-1 1h-4v-7H9v7H5a1 1 0 01-1-1v-9z"/></g>,
    document:   <g {...p}><path d="M6 3h8l4 4v13a1 1 0 01-1 1H6a1 1 0 01-1-1V4a1 1 0 011-1zM14 3v4h4"/></g>,
    flame:      <g {...p}><path d="M12 3c0 4 4 5 4 10a4 4 0 11-8 0c0-2 1-3 1-5 0 1 1 2 2 2 0-3 1-5 1-7z"/></g>,
    person:     <g {...p}><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-7 8-7s8 3 8 7"/></g>,
    bullet:     <circle cx="12" cy="12" r="3" {...f}/>,
    ring:       <g><circle cx="12" cy="12" r="9" stroke={color} strokeWidth="2" fill="none"/></g>,
    minus:      <g {...p} strokeWidth={2}><path d="M5 12h14"/></g>,
    arrowR:     <g {...p}><path d="M5 12h14M14 7l5 5-5 5"/></g>,
    expand:     <g {...p}><path d="M4 10V4h6M20 10V4h-6M4 14v6h6M20 14v6h-6"/></g>,
    layers:     <g {...p}><path d="M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5M3 17l9 5 9-5"/></g>,
    branch:     <g {...p}><circle cx="6" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="12" r="2"/><path d="M6 8v8M6 12h6a4 4 0 004-4"/></g>,
  };
  return (
    <svg width={s} height={s} viewBox="0 0 24 24" {...rest}>{paths[name] || null}</svg>
  );
};

// ── Stack utility ───────────────────────────────────────────────
const Stack = ({ dir = 'col', gap = 0, align, justify, style, children, ...rest }) => (
  <div style={{
    display: 'flex',
    flexDirection: dir === 'row' ? 'row' : 'column',
    gap, alignItems: align, justifyContent: justify, ...style,
  }} {...rest}>{children}</div>
);

// ── Theme wrapper artboard ──────────────────────────────────────
const ThemeRoot = ({ theme = 'light', density = 'comfortable', children, style }) => (
  <div className={`lists-root theme-${theme} density-${density}`}
    style={{ width: '100%', height: '100%', overflow: 'hidden', ...style }}>
    {children}
  </div>
);

// ── Round, sage-tinted icon badge for sidebar list rows ──────────
const IconBadge = ({ icon, hue = 'var(--hue-grey)', s = 28, glyph = 14 }) => (
  <div style={{
    width: s, height: s, borderRadius: '50%',
    background: hue,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    color: '#fff', flexShrink: 0,
  }}>
    <Icon name={icon} s={glyph} strokeWidth={1.9} />
  </div>
);

// ── Round checkbox (task) — tap target 28×28, glyph 22 ──────────
const Checkbox = ({ checked = false, color = 'var(--accent)', size = 22, partial = false }) => (
  <div style={{
    width: size, height: size, borderRadius: '50%',
    border: `1.6px solid ${checked ? color : 'var(--fg-tertiary)'}`,
    background: checked ? color : 'transparent',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    flexShrink: 0,
    boxShadow: checked ? '0 1px 2px rgba(0,0,0,.08)' : 'none',
    transition: 'all 160ms var(--ease-standard)',
  }}>
    {checked && <Icon name="checkBold" s={size - 8} color="var(--accent-on)" />}
    {partial && !checked && (
      <div style={{ width: size * 0.45, height: 2, background: color, borderRadius: 1 }} />
    )}
  </div>
);

// ── Habit counter ring (small, in-row) ──────────────────────────
const HabitRing = ({ count = 3, goal = 8, size = 26, color = 'var(--accent)' }) => {
  const r = size / 2 - 2.5;
  const c = 2 * Math.PI * r;
  const pct = Math.min(1, count / goal);
  return (
    <div style={{ width: size, height: size, position: 'relative', flexShrink: 0 }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size/2} cy={size/2} r={r} stroke="var(--sep-opaque)" strokeWidth="2.2" fill="none" />
        <circle cx={size/2} cy={size/2} r={r} stroke={color} strokeWidth="2.6" fill="none"
          strokeDasharray={c} strokeDashoffset={c * (1 - pct)} strokeLinecap="round" />
      </svg>
      <div className="mono" style={{
        position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 9, fontWeight: 600, color: 'var(--fg-secondary)', lineHeight: 1,
      }}>{count}</div>
    </div>
  );
};

// ── Tag chip (#tag) ─────────────────────────────────────────────
const Tag = ({ label, color = 'var(--accent-tint-fg)', bg = 'var(--accent-tint-bg)' }) => (
  <span style={{
    display: 'inline-flex', alignItems: 'center',
    height: 20, padding: '0 8px', borderRadius: 999,
    background: bg, color, fontSize: 12, fontWeight: 600,
    fontFamily: 'var(--font-mono)', letterSpacing: 0,
  }}>#{label}</span>
);

// ── Priority bar (vertical |||) ─────────────────────────────────
const Priority = ({ level = 'medium' }) => {
  const lvl = { none: 0, low: 1, medium: 2, high: 3 }[level] || 0;
  if (!lvl) return null;
  const color = lvl === 3 ? 'var(--danger)' : lvl === 2 ? 'var(--warn)' : 'var(--fg-tertiary)';
  return (
    <div style={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
      {[1,2,3].map(i => (
        <div key={i} style={{
          width: 2.5, height: 11, borderRadius: 1.5,
          background: i <= lvl ? color : 'var(--sep-opaque)',
        }}/>
      ))}
    </div>
  );
};

// ── Subtree progress badge (3/5) ────────────────────────────────
const SubtreeBadge = ({ done, total, complete = false }) => (
  <span className="mono" style={{
    fontSize: 11, fontWeight: 600,
    color: complete ? 'var(--accent)' : 'var(--fg-tertiary)',
    padding: '2px 6px', borderRadius: 5,
    background: complete ? 'var(--accent-soft)' : 'var(--bg-surface-2)',
    letterSpacing: 0, lineHeight: 1.2, height: 18, display: 'inline-flex', alignItems: 'center',
  }}>{done}/{total}</span>
);

// ── List row (task / habit / note) ──────────────────────────────
const ListRow = ({
  type = 'task', title, body, time, due, done = false, partial = false,
  reminder = false, location = false, urgent = false, recurring = false,
  flagged = false, priority, tags = [], subtree, habit, color = 'var(--accent)',
  isLast, indent = 0, agent = false,
}) => {
  const showTitleColor = done ? 'var(--fg-tertiary)' : 'var(--fg-primary)';
  return (
    <div style={{
      position: 'relative', display: 'flex', gap: 12,
      padding: 'var(--row-pad-y) var(--row-pad-x)',
      paddingLeft: `calc(var(--row-pad-x) + ${indent * 28}px)`,
      minHeight: 'var(--row-h)', alignItems: 'flex-start',
    }}>
      <div style={{ paddingTop: 1, flexShrink: 0 }}>
        {type === 'task' && <Checkbox checked={done} partial={partial} color={color} />}
        {type === 'habit' && <HabitRing count={habit?.count ?? 3} goal={habit?.goal ?? 8} color={color} />}
        {type === 'note' && (
          <div style={{ width: 22, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-tertiary)' }}>
            <Icon name="document" s={17} strokeWidth={1.5} />
          </div>
        )}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', minHeight: 22 }}>
          <span style={{
            fontSize: 'var(--t-body)', lineHeight: 1.3, fontWeight: 500,
            color: showTitleColor,
            textDecoration: done ? 'line-through' : 'none',
            textDecorationColor: 'var(--fg-tertiary)',
            textDecorationThickness: '1.5px',
          }}>{title}</span>
          {flagged && <Icon name="flagFill" s={13} color="var(--warn)" />}
          {urgent && <Icon name="bolt" s={13} color="var(--danger)" />}
          {priority && <Priority level={priority} />}
          {subtree && <SubtreeBadge {...subtree} />}
        </div>
        {body && (
          <div style={{
            fontSize: 'var(--t-footnote)', color: 'var(--fg-secondary)',
            marginTop: 2, lineHeight: 1.3,
            overflow: 'hidden', textOverflow: 'ellipsis',
            display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical',
          }}>{body}</div>
        )}
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: (time || due || tags.length) ? 4 : 0, flexWrap: 'wrap' }}>
          {due && (
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 3,
              fontSize: 'var(--t-caption1)', fontWeight: 500,
              color: due.overdue ? 'var(--danger)' : 'var(--accent-tint-fg)',
              fontFamily: 'var(--font-mono)', letterSpacing: 0,
            }}>
              {due.label}
            </span>
          )}
          {time && (
            <span className="mono" style={{ fontSize: 'var(--t-caption1)', color: 'var(--fg-secondary)', fontWeight: 500 }}>{time}</span>
          )}
          {reminder === true && <Icon name="bell" s={12} color="var(--fg-tertiary)" />}
          {reminder === 'silent' && <Icon name="bellSlash" s={12} color="var(--fg-tertiary)" />}
          {recurring && <Icon name="repeat" s={12} color="var(--fg-tertiary)" />}
          {location && <Icon name="location" s={12} color="var(--fg-tertiary)" />}
          {agent && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3,
              fontSize: 11, color: 'var(--accent-tint-fg)', fontWeight: 600,
              padding: '1px 6px', borderRadius: 4, background: 'var(--accent-soft)',
              fontFamily: 'var(--font-mono)', letterSpacing: 0,
            }}><Icon name="cpu" s={10} /> {agent}</span>
          )}
          {tags.map(t => <Tag key={t} label={t} />)}
        </div>
      </div>
    </div>
  );
};

// ── Section header inside a list ────────────────────────────────
// Title Case label, hairline divider sits ABOVE the header.
const SectionHead = ({ title, count, collapsed, color, hideDivider = false }) => (
  <>
    {!hideDivider && (
      <div style={{ height: 0.5, background: 'var(--sep-translucent)', margin: '14px 16px 0', transform: 'scaleY(0.5)', transformOrigin: 'top' }} />
    )}
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '12px 16px 6px',
      fontSize: 14, fontWeight: 600, letterSpacing: 0,
      color: color || 'var(--fg-secondary)',
    }}>
      {collapsed !== undefined && (
        <Icon name={collapsed ? 'chevronR' : 'chevronD'} s={12} color="var(--fg-tertiary)" />
      )}
      <span>{title}</span>
      {count !== undefined && (
        <span className="mono" style={{ fontWeight: 500, color: 'var(--fg-tertiary)', letterSpacing: 0, fontSize: 13 }}>{count}</span>
      )}
    </div>
  </>
);

// ── Sidebar row (smartlist / list / sub-list) ───────────────────
const SidebarRow = ({ icon, hue, label, count, active, indent = 0, presence, agent }) => (
  <div style={{
    display: 'flex', alignItems: 'center', gap: 12,
    padding: '8px 12px', paddingLeft: 12 + indent * 20,
    borderRadius: 8,
    background: active ? 'var(--accent-soft)' : 'transparent',
    color: active ? 'var(--accent-tint-fg)' : 'var(--fg-primary)',
    fontSize: 'var(--t-callout)', fontWeight: active ? 600 : 500,
    minHeight: 36,
  }}>
    {icon && <IconBadge icon={icon} hue={hue || 'var(--hue-grey)'} s={26} glyph={13} />}
    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
    {presence && (
      <div style={{
        width: 7, height: 7, borderRadius: 7, background: 'var(--accent)',
        boxShadow: '0 0 0 0 var(--accent-soft)',
      }} />
    )}
    {agent && (
      <span className="mono" style={{ fontSize: 10, color: 'var(--accent-tint-fg)', fontWeight: 600, letterSpacing: 0 }}>{agent}</span>
    )}
    {count !== undefined && (
      <span className="mono" style={{ fontSize: 13, color: 'var(--fg-tertiary)', fontWeight: 500, letterSpacing: 0 }}>{count}</span>
    )}
  </div>
);

// ── FAB (floating + button) ─────────────────────────────────────
const FAB = ({ size = 56 }) => (
  <div style={{
    position: 'absolute', bottom: 24, right: 20, zIndex: 30,
    width: size, height: size, borderRadius: size/2,
    background: 'var(--accent)', color: 'var(--accent-on)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    boxShadow: '0 8px 22px var(--accent-soft), 0 2px 6px rgba(0,0,0,.12)',
  }}>
    <Icon name="plusBold" s={26} color="var(--accent-on)" />
  </div>
);

// ── Inset card — flush plain-list container (no rounded surface)
// Items sit directly on the grouped bg with hairline separators between rows.
const InsetCard = ({ children, style }) => (
  <div style={{
    margin: '0 16px',
    ...style,
  }}>{children}</div>
);

// ── Row separator (full-width hairline; left-inset to clear leading icon) ──
const Separator = ({ inset = 50 }) => (
  <div style={{
    height: 0.5, background: 'var(--sep-translucent)',
    marginLeft: inset, transform: 'scaleY(0.5)', transformOrigin: 'top',
  }}/>
);

// ── Phone-shaped device frame (lighter than full IOSDevice) ─────
const PhoneFrame = ({ children, dark = false, time = '9:41', width = 393, height = 852, statusBg, hideStatus = false, hideHomebar = false }) => (
  <div style={{
    width, height, borderRadius: 48, position: 'relative', overflow: 'hidden',
    background: dark ? '#000' : 'var(--bg-grouped)',
    boxShadow: '0 0 0 1px rgba(0,0,0,0.10), 0 28px 60px rgba(0,0,0,0.16)',
    fontFamily: 'var(--font-rounded)',
  }}>
    {!hideStatus && (
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 54, zIndex: 50, background: statusBg || 'transparent', pointerEvents: 'none' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', padding: '18px 36px 0', alignItems: 'center', color: dark ? '#fff' : 'var(--fg-primary)' }}>
          <span style={{ fontSize: 16, fontWeight: 600, fontFamily: 'var(--font-rounded)' }}>{time}</span>
          <div style={{ width: 110, height: 32, background: '#000', borderRadius: 20, position: 'absolute', left: '50%', top: 11, transform: 'translateX(-50%)' }} />
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <svg width="18" height="11" viewBox="0 0 18 11"><g fill={dark ? '#fff' : '#000'}>
              <rect x="0" y="7" width="3" height="4" rx="0.6"/>
              <rect x="4.5" y="5" width="3" height="6" rx="0.6"/>
              <rect x="9" y="2.5" width="3" height="8.5" rx="0.6"/>
              <rect x="13.5" y="0" width="3" height="11" rx="0.6"/>
            </g></svg>
            <svg width="24" height="12" viewBox="0 0 24 12">
              <rect x="0.5" y="0.5" width="20" height="11" rx="3" fill="none" stroke={dark ? '#fff' : '#000'} strokeOpacity={0.3}/>
              <rect x="2" y="2" width="17" height="8" rx="1.6" fill={dark ? '#fff' : '#000'}/>
              <rect x="22" y="3.5" width="1.5" height="5" rx="0.6" fill={dark ? '#fff' : '#000'} fillOpacity="0.4"/>
            </svg>
          </div>
        </div>
      </div>
    )}
    <div style={{ position: 'absolute', inset: 0 }}>{children}</div>
    {!hideHomebar && (
      <div style={{ position: 'absolute', bottom: 8, left: 0, right: 0, height: 4, display: 'flex', justifyContent: 'center', zIndex: 60, pointerEvents: 'none' }}>
        <div style={{ width: 134, height: 4, borderRadius: 2, background: dark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.25)' }} />
      </div>
    )}
  </div>
);

// ── Heatmap cell ────────────────────────────────────────────────
const heatColor = (count, goal) => {
  if (!count) return 'var(--hm-empty)';
  const pct = count / goal;
  if (pct >= 1) return 'var(--hm-4)';
  if (pct >= 0.66) return 'var(--hm-3)';
  if (pct >= 0.33) return 'var(--hm-2)';
  return 'var(--hm-1)';
};

Object.assign(window, {
  Icon, Stack, ThemeRoot, IconBadge, Checkbox, HabitRing, Tag, Priority,
  SubtreeBadge, ListRow, SectionHead, SidebarRow, FAB, InsetCard, Separator,
  PhoneFrame, heatColor,
});
