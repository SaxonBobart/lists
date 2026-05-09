/* Lists — Sheets & specialized screens */

// ── Create sheet ────────────────────────────────────────────────
const ItemSheet = ({ dark = false }) => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', position: 'relative', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    {/* Sheet pill grabber */}
    <div style={{ display: 'flex', justifyContent: 'center', padding: '6px 0' }}>
      <div style={{ width: 36, height: 5, borderRadius: 3, background: 'var(--fg-quaternary)' }} />
    </div>

    {/* Sheet header */}
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '4px 16px 10px' }}>
      <span style={{ color: 'var(--fg-secondary)', fontSize: 16, fontWeight: 500 }}>Cancel</span>
      <span style={{ fontSize: 17, fontWeight: 700, color: 'var(--fg-primary)' }}>New Item</span>
      <span style={{ color: 'var(--accent)', fontSize: 16, fontWeight: 600 }}>Add</span>
    </div>

    <div style={{ overflow: 'auto', flex: 1 }}>
      {/* Title + tag chip area + notes (expandable) */}
      <InsetCard>
        {/* Title row with caret */}
        <div style={{ padding: '14px 16px 4px', display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <Checkbox checked={false} />
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 2, minHeight: 28 }}>
            <span style={{ fontSize: 'var(--t-title2)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.2, lineHeight: 1.2 }}>
              Email Sarah about the contract
            </span>
            <span style={{ width: 2, height: 22, background: 'var(--accent)', display: 'inline-block', animation: 'caret 1s steps(2,end) infinite', marginLeft: 1, borderRadius: 1 }} />
          </div>
        </div>

        {/* Tag chip line — small, tappable, becomes input on focus */}
        <div style={{ padding: '4px 16px 6px 56px', display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
          <Tag label="work" />
          <Tag label="legal" />
          <span style={{
            fontSize: 12, color: 'var(--fg-tertiary)', fontFamily: 'var(--font-mono)',
            display: 'inline-flex', alignItems: 'center', gap: 4,
          }}>
            <Icon name="plus" s={11} color="var(--fg-tertiary)" strokeWidth={2.2}/> tag
          </span>
        </div>

        <Separator inset={56}/>

        {/* Notes preview with expand */}
        <div style={{ padding: '10px 16px 12px 56px', display: 'flex', alignItems: 'flex-start', gap: 8 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, color: 'var(--fg-secondary)', lineHeight: 1.45, overflow: 'hidden', textOverflow: 'ellipsis', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
              Pull final voice samples from spec v2 and ship to Sarah for review by EOW.
            </div>
          </div>
          <div style={{
            width: 26, height: 26, borderRadius: 13,
            background: 'var(--bg-surface-2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <Icon name="expand" s={12} color="var(--fg-secondary)" strokeWidth={2}/>
          </div>
        </div>
      </InsetCard>

      {/* Date & Time */}
      <SectionHead title="Date & Time" />
      <InsetCard>
        <SheetRow icon="calendar" hue="var(--hue-orange)" label="Date" value="Mon, May 11"/>
        <Separator inset={56}/>
        <SheetRow icon="clock" hue="var(--hue-blue)" label="Time" value="9:00 AM"/>
        <Separator inset={56}/>
        <SheetRow icon="bolt" hue="var(--danger)" label="Urgent" toggle off/>
        <Separator inset={56}/>
        <SheetRow icon="location" hue="var(--hue-green)" label="Location" value="None" subtle/>
      </InsetCard>

      {/* Organization */}
      <SectionHead title="Organization" />
      <InsetCard>
        <SheetRow icon="flag" hue="var(--warn)" label="Flag" toggle off/>
        <Separator inset={56}/>
        <SheetRow icon="bullet" hue="var(--warn)" label="Priority" value="High"/>
        <Separator inset={56}/>
        <SheetRow icon="layers" hue="var(--hue-purple)" label="Section" value="This Afternoon"/>
        <Separator inset={56}/>
        <SheetRow icon="branch" hue="var(--hue-blue)" label="Sub-items" value="None" subtle/>
        <Separator inset={56}/>
        <SheetRow icon="folder" hue="var(--accent)" label="List" value="Apollo"/>
      </InsetCard>

      <div style={{ height: 16 }} />
    </div>

    {/* Above-keyboard accessory bar */}
    <div style={{
      background: 'var(--bg-surface-2)',
      borderTop: '0.5px solid var(--sep-translucent)',
      padding: '8px 6px',
      display: 'flex', gap: 4, alignItems: 'center', justifyContent: 'space-around',
    }}>
      {[
        { i: 'tag', l: 'Tag' },
        { i: 'calendar', l: 'Date' },
        { i: 'location', l: 'Location' },
        { i: 'flag', l: 'Flag' },
        { i: 'bullet', l: 'Priority' },
      ].map(c => (
        <div key={c.l} style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
          padding: '6px 10px', borderRadius: 10,
          minWidth: 56,
        }}>
          <Icon name={c.i} s={20} color="var(--accent)" strokeWidth={2}/>
          <span style={{ fontSize: 10, color: 'var(--fg-secondary)', fontWeight: 500 }}>{c.l}</span>
        </div>
      ))}
    </div>
  </div>
);

const SheetRow = ({ icon, hue, label, value, toggle, on, info, subtle }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', minHeight: 48 }}>
    <IconBadge icon={icon} hue={hue} s={28} glyph={15} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 16, fontWeight: 500, color: subtle ? 'var(--fg-secondary)' : 'var(--fg-primary)' }}>{label}</div>
      {info && <div style={{ fontSize: 11, color: 'var(--fg-tertiary)', marginTop: 2 }}>{info}</div>}
    </div>
    {value !== undefined && (
      <span style={{ fontSize: 15, color: 'var(--accent-tint-fg)', fontFamily: 'var(--font-mono)', letterSpacing: 0 }}>{value}</span>
    )}
    {toggle && <Switch on={!!on} />}
    {!toggle && value === undefined && <Icon name="chevronR" s={14} color="var(--fg-tertiary)" />}
  </div>
);

const Switch = ({ on = true }) => (
  <div style={{
    width: 50, height: 30, borderRadius: 15,
    background: on ? 'var(--accent)' : 'var(--fg-quaternary)',
    position: 'relative', flexShrink: 0,
    transition: 'background 200ms var(--ease-standard)',
  }}>
    <div style={{
      width: 26, height: 26, borderRadius: 13, background: '#fff',
      position: 'absolute', top: 2, left: on ? 22 : 2,
      boxShadow: '0 1px 3px rgba(0,0,0,.2)',
      transition: 'left 200ms var(--ease-standard)',
    }} />
  </div>
);

// ── Habit detail with heatmap ───────────────────────────────────
// Three style variants: 'square' | 'rounded' | 'dot'
const HabitDetail = ({ variant = 'rounded' }) => {
  // Generate one year of fake completion data (deterministic noise)
  const cells = Array.from({ length: 365 }, (_, i) => {
    const seed = (i * 9301 + 49297) % 233280;
    const r = seed / 233280;
    if (i < 30) return r > 0.85 ? 0 : Math.ceil(r * 8);
    if (r < 0.2) return 0;
    if (r < 0.5) return Math.ceil(r * 6);
    return 8;
  });
  const goal = 8;

  return (
    <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
      <div style={{ padding: '4px 16px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center', color: 'var(--accent)', fontSize: 15, fontWeight: 500, marginBottom: 4 }}>
            <Icon name="chevronR" s={11} color="var(--accent)" style={{ transform: 'scaleX(-1)' }} /> Habits
          </div>
          <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Drink water</div>
          <div style={{ display: 'flex', gap: 8, marginTop: 4, fontSize: 12, color: 'var(--fg-secondary)' }}>
            <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}><Icon name="repeat" s={11} /> Daily</span>
            <span>·</span>
            <span>Goal 8 / day</span>
          </div>
        </div>
        <CircleBtn icon="moreH" />
      </div>

      {/* Counter bar */}
      <div style={{ margin: '4px 16px 14px', padding: 16, background: 'var(--bg-elevated)', borderRadius: 16, display: 'flex', alignItems: 'center', gap: 14, boxShadow: '0 1px 0 var(--sep-opaque) inset' }}>
        <HabitRing count={5} goal={8} size={56} />
        <div style={{ flex: 1 }}>
          <div className="mono" style={{ fontSize: 28, fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: 0, lineHeight: 1 }}>5<span style={{ color: 'var(--fg-tertiary)', fontWeight: 500 }}>/8</span></div>
          <div style={{ fontSize: 12, color: 'var(--fg-secondary)', marginTop: 2 }}>3 to go today</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <div style={{ width: 36, height: 36, borderRadius: 18, background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-secondary)' }}>
            <Icon name="minus" s={18} color="var(--fg-secondary)" />
          </div>
          <div style={{ width: 44, height: 44, borderRadius: 22, background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-on)', boxShadow: '0 4px 10px var(--accent-soft)' }}>
            <Icon name="plusBold" s={22} color="var(--accent-on)" />
          </div>
        </div>
      </div>

      {/* Stats strip */}
      <div style={{ display: 'flex', gap: 8, padding: '0 16px', marginBottom: 14 }}>
        <StatCard label="Streak" value="12" unit="days" icon="flame" hue="var(--warn)" />
        <StatCard label="Best" value="34" unit="days" hue="var(--accent)" />
        <StatCard label="This year" value="248" unit="of 365" hue="var(--hue-blue)" />
      </div>

      {/* Heatmap */}
      <div style={{ padding: '0 16px', flex: 1, overflow: 'auto', paddingBottom: 24 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8, display: 'flex', justifyContent: 'space-between' }}>
          <span>Last year</span>
          <span className="mono" style={{ fontWeight: 500, color: 'var(--fg-tertiary)' }}>v: {variant}</span>
        </div>
        <div style={{ background: 'var(--bg-elevated)', borderRadius: 14, padding: 14, boxShadow: '0 1px 0 var(--sep-opaque) inset' }}>
          <Heatmap variant={variant} cells={cells} goal={goal} />
          <Legend variant={variant} />
        </div>

        {/* Edit history teaser */}
        <div style={{ marginTop: 14, padding: '14px 16px', background: 'var(--bg-elevated)', borderRadius: 14, display: 'flex', alignItems: 'center', gap: 10 }}>
          <IconBadge icon="clock" hue="var(--hue-grey)" s={28} glyph={15} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 15, fontWeight: 500, color: 'var(--fg-primary)' }}>Edit history</div>
            <div style={{ fontSize: 12, color: 'var(--fg-tertiary)' }}>Backfill or correct any past day</div>
          </div>
          <Icon name="chevronR" s={14} color="var(--fg-tertiary)" />
        </div>
      </div>
    </div>
  );
};

const StatCard = ({ label, value, unit, icon, hue }) => (
  <div style={{ flex: 1, background: 'var(--bg-elevated)', borderRadius: 12, padding: 12, boxShadow: '0 1px 0 var(--sep-opaque) inset' }}>
    <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 11, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 600 }}>
      {icon && <Icon name={icon} s={11} color={hue} />} {label}
    </div>
    <div style={{ marginTop: 4, display: 'flex', alignItems: 'baseline', gap: 4 }}>
      <span className="mono" style={{ fontSize: 22, fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: 0, lineHeight: 1 }}>{value}</span>
      <span style={{ fontSize: 11, color: 'var(--fg-tertiary)' }}>{unit}</span>
    </div>
  </div>
);

const Heatmap = ({ variant = 'rounded', cells, goal }) => {
  // 7 rows × 53 cols
  const rows = 7, cols = 53;
  const grid = Array.from({ length: rows }, () => new Array(cols).fill(null));
  cells.forEach((c, i) => {
    const col = Math.floor(i / 7);
    const row = i % 7;
    if (col < cols && row < rows) grid[row][col] = c;
  });
  const cellSize = variant === 'dot' ? 6 : 10;
  const cellGap = 2;

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, color: 'var(--fg-tertiary)', fontFamily: 'var(--font-mono)', marginBottom: 4, letterSpacing: 0 }}>
        {['May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar','Apr'].map(m => <span key={m}>{m}</span>)}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, ${cellSize}px)`, gridTemplateRows: `repeat(${rows}, ${cellSize}px)`, gap: cellGap, gridAutoFlow: 'column' }}>
        {Array.from({ length: rows * cols }).map((_, i) => {
          const col = Math.floor(i / rows), row = i % rows;
          const v = grid[row][col];
          const bg = v == null ? 'transparent' : heatColor(v, goal);
          if (variant === 'square') {
            return <div key={i} style={{ width: cellSize, height: cellSize, background: bg, borderRadius: 1 }} />;
          }
          if (variant === 'dot') {
            return <div key={i} style={{ width: cellSize, height: cellSize, background: bg, borderRadius: '50%' }} />;
          }
          return <div key={i} style={{ width: cellSize, height: cellSize, background: bg, borderRadius: 3 }} />;
        })}
      </div>
    </div>
  );
};

const Legend = ({ variant }) => {
  const cellSize = variant === 'dot' ? 8 : 10;
  const r = variant === 'dot' ? '50%' : variant === 'square' ? 1 : 3;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 10, fontSize: 11, color: 'var(--fg-tertiary)' }}>
      <span>Less</span>
      {['var(--hm-empty)','var(--hm-1)','var(--hm-2)','var(--hm-3)','var(--hm-4)'].map(c => (
        <div key={c} style={{ width: cellSize, height: cellSize, background: c, borderRadius: r }} />
      ))}
      <span>More</span>
    </div>
  );
};

// ── Inline edit + keyboard accessory bar ────────────────────────
const InlineEditScreen = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px' }}>
      <div style={{ fontSize: 13, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 600 }}>Friday, May 8</div>
      <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)' }}>Today</div>
    </div>
    <div style={{ flex: 1, overflow: 'hidden', paddingBottom: 0 }}>
      <SectionHead title="This Afternoon" count={2} />
      <InsetCard>
        <ListRow type="task" title="Pick up dry cleaning" time="2:30 PM" reminder location />
        <Separator/>
        {/* Inline-editing row */}
        <div style={{ padding: '12px 16px', display: 'flex', gap: 12, background: 'var(--accent-soft)' }}>
          <Checkbox checked={false} />
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ fontSize: 'var(--t-body)', fontWeight: 500, color: 'var(--fg-primary)' }}>Email Sarah about contract</span>
            <span style={{ width: 1.5, height: 18, background: 'var(--accent)', display: 'inline-block', animation: 'caret 1s steps(2,end) infinite', marginLeft: 1 }} />
          </div>
        </div>
        <Separator/>
        <ListRow type="task" title="Draft v1.0 release notes" time="3:00 PM" priority="medium" subtree={{done: 2, total: 4}} />
      </InsetCard>
    </div>

    {/* Keyboard accessory bar */}
    <div style={{
      background: 'var(--bg-surface-2)',
      borderTop: '0.5px solid var(--sep-translucent)',
      padding: '8px 12px',
      display: 'flex', gap: 8, alignItems: 'center', overflowX: 'auto',
    }}>
      {[
        { i: 'calendar', l: 'Today' },
        { i: 'bell', l: '15m' },
        { i: 'tag', l: '#work' },
        { i: 'flag', l: 'Med' },
        { i: 'folder', l: 'Apollo' },
        { i: 'moreH', l: 'More' },
      ].map(c => (
        <div key={c.i} style={{
          display: 'flex', alignItems: 'center', gap: 5,
          padding: '7px 11px', background: 'var(--bg-elevated)', borderRadius: 8,
          fontSize: 13, color: 'var(--fg-primary)', fontWeight: 500,
          flexShrink: 0,
          boxShadow: '0 1px 0 rgba(0,0,0,.04)',
        }}>
          <Icon name={c.i} s={14} color="var(--accent)" /> {c.l}
        </div>
      ))}
    </div>

    {/* Keyboard placeholder */}
    <div style={{ height: 280, background: 'var(--bg-surface-2)', borderTop: '0.5px solid var(--sep-translucent)', position: 'relative' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(10, 1fr)', gap: 6, padding: '10px 6px' }}>
        {'qwertyuiopasdfghjkl  zxcvbnm  '.split('').map((c, i) => (
          <div key={i} style={{
            height: 40, background: c.trim() ? 'var(--bg-elevated)' : 'transparent',
            borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 18, color: 'var(--fg-primary)', fontWeight: 400,
            gridColumn: i === 19 ? '2 / span 1' : i === 20 ? 'span 2' : 'auto',
          }}>{c.trim() && c.toUpperCase()}</div>
        ))}
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 40, display: 'flex', gap: 6, padding: '0 6px 8px' }}>
        <div style={{ width: 60, background: 'var(--bg-elevated)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: 'var(--fg-secondary)' }}>123</div>
        <div style={{ flex: 1, background: 'var(--bg-elevated)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: 'var(--fg-secondary)' }}>space</div>
        <div style={{ width: 80, background: 'var(--accent)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: 'var(--accent-on)', fontWeight: 600 }}>return</div>
      </div>
    </div>
  </div>
);

Object.assign(window, { ItemSheet, SheetRow, Switch, HabitDetail, Heatmap, Legend, StatCard, InlineEditScreen });
