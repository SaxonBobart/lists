/* Lists — Novelty / alternate directions
 *  A. Calendar-Day Today (time-spine layout, novel)
 *  B. Tot-style color-as-nav (color-coded list switcher)
 *  C. Editorial Today (single-column, large type, iA-Writer-flavored)
 */

// ── A. Time-spine Today ─────────────────────────────────────────
const TimeSpineToday = () => {
  const hours = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18];
  const items = [
    { hour: 6, dur: 1, title: 'Run 5km', type: 'task', done: true, hue: 'var(--hue-green)' },
    { hour: 7, dur: 0.5, title: 'Meditate', type: 'habit', habit: { count: 1, goal: 1 }, hue: 'var(--accent)' },
    { hour: 9, dur: 1, title: 'Standup', type: 'task', tags: ['agents'], hue: 'var(--hue-blue)' },
    { hour: 14, dur: 0.75, title: 'Pick up dry cleaning', type: 'task', location: true, hue: 'var(--hue-orange)' },
    { hour: 15, dur: 1.25, title: 'Draft v1.0 release notes', type: 'task', subtree: {done:2,total:4}, hue: 'var(--accent)' },
    { hour: 17, dur: 0.5, title: 'Call Mum', type: 'task', flagged: true, hue: 'var(--hue-pink)' },
  ];
  const ROW = 56;
  const now = 14.4; // 2:24 PM "now line"

  return (
    <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
      <div style={{ padding: '4px 16px 12px' }}>
        <div style={{ fontSize: 13, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 600 }}>Friday, May 8</div>
        <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Today</div>
        <div style={{ fontSize: 12, color: 'var(--fg-tertiary)', marginTop: 2 }}>6 scheduled · 2 anytime</div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', position: 'relative' }}>
        <div style={{ position: 'relative', padding: '0 16px 80px', minHeight: hours.length * ROW + 30 }}>
          {/* Hour rows */}
          {hours.map((h, i) => (
            <div key={h} style={{
              position: 'absolute', top: i * ROW, left: 16, right: 16, height: ROW,
              borderTop: '0.5px solid var(--sep-translucent)',
              display: 'flex', alignItems: 'flex-start', paddingTop: 4,
            }}>
              <div className="mono" style={{
                fontSize: 11, fontWeight: 500, color: 'var(--fg-tertiary)',
                width: 44, letterSpacing: 0,
              }}>{h % 12 === 0 ? 12 : h % 12}{h < 12 ? ' AM' : ' PM'}</div>
            </div>
          ))}
          {/* Now line */}
          <div style={{
            position: 'absolute', top: (now - 6) * ROW - 1, left: 16, right: 16,
            height: 2, background: 'var(--danger)', borderRadius: 2,
            boxShadow: '0 0 0 4px rgba(255,80,60,.08)',
          }}>
            <div style={{ position: 'absolute', left: -4, top: -3, width: 8, height: 8, borderRadius: 4, background: 'var(--danger)' }} />
            <div className="mono" style={{ position: 'absolute', right: 0, top: -16, fontSize: 9, color: 'var(--danger)', fontWeight: 600 }}>NOW · 2:24</div>
          </div>
          {/* Items */}
          {items.map((it, i) => (
            <div key={i} style={{
              position: 'absolute', top: (it.hour - 6) * ROW + 6, left: 64, right: 16,
              height: it.dur * ROW - 8,
              background: 'var(--bg-elevated)',
              borderLeft: `3px solid ${it.hue}`,
              borderRadius: 8, padding: '8px 12px',
              boxShadow: '0 1px 4px rgba(0,0,0,.04), 0 0 0 0.5px var(--sep-translucent)',
              display: 'flex', gap: 10, alignItems: 'flex-start',
              opacity: it.done ? 0.55 : 1,
            }}>
              {it.type === 'task' && <Checkbox checked={it.done} color={it.hue} />}
              {it.type === 'habit' && <HabitRing count={it.habit.count} goal={it.habit.goal} color={it.hue} />}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: it.done ? 'var(--fg-tertiary)' : 'var(--fg-primary)', textDecoration: it.done ? 'line-through' : 'none' }}>
                  {it.title}
                  {it.flagged && <Icon name="flagFill" s={12} color="var(--warn)" style={{ marginLeft: 6 }}/>}
                </div>
                <div style={{ display: 'flex', gap: 6, marginTop: 4, alignItems: 'center', flexWrap: 'wrap' }}>
                  {it.subtree && <SubtreeBadge {...it.subtree} />}
                  {it.location && <Icon name="location" s={11} color="var(--fg-tertiary)" />}
                  {(it.tags||[]).map(t => <Tag key={t} label={t} />)}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <FAB />
    </div>
  );
};

// ── B. Tot-style color-coded list switcher ──────────────────────
const TotStyleScreen = () => {
  const dots = [
    { hue: 'var(--accent)', label: 'Today', active: true },
    { hue: 'var(--hue-orange)', label: 'Apollo' },
    { hue: 'var(--hue-blue)', label: 'Personal' },
    { hue: 'var(--hue-green)', label: 'Groceries' },
    { hue: 'var(--hue-purple)', label: 'Reading' },
    { hue: 'var(--hue-pink)', label: 'Wishlist' },
    { hue: 'var(--hue-grey)', label: 'Notes' },
  ];
  return (
    <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
      {/* Color-dot bar */}
      <div style={{
        padding: '8px 18px 12px',
        display: 'flex', justifyContent: 'space-between',
        borderBottom: '0.5px solid var(--sep-translucent)',
      }}>
        {dots.map((d, i) => (
          <div key={i} style={{ position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
            <div style={{
              width: 22, height: 22, borderRadius: 11,
              background: d.hue,
              boxShadow: d.active ? `0 0 0 3px var(--bg-grouped), 0 0 0 4.5px ${d.hue}` : 'none',
            }} />
            {d.active && <div className="mono" style={{ fontSize: 9, fontWeight: 600, color: 'var(--fg-primary)', letterSpacing: 0 }}>{d.label}</div>}
          </div>
        ))}
      </div>

      {/* Single-list content */}
      <div style={{ flex: 1, padding: '24px 24px 80px', overflow: 'auto' }}>
        <div style={{ fontSize: 13, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 600 }}>Friday</div>
        <div style={{ fontSize: 32, fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4, marginBottom: 18 }}>Today</div>

        {[
          { t: 'Reply to Ada about the venue', overdue: true },
          { t: 'Run 5km', done: true, time: '6:30 AM' },
          { t: 'Standup with the agentic-coding crew', time: '9:00 AM', reminder: true },
          { t: 'Pick up dry cleaning', time: '2:30 PM', location: true },
          { t: 'Draft v1.0 release notes', time: '3:00 PM', subtree: {done:2,total:4} },
          { t: 'Call Mum', time: '5:00 PM', flagged: true },
        ].map((it, i) => (
          <div key={i} style={{ display: 'flex', gap: 14, padding: '12px 0', borderBottom: '0.5px solid var(--sep-translucent)', alignItems: 'flex-start' }}>
            <Checkbox checked={it.done} />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 17, fontWeight: 500, color: it.done ? 'var(--fg-tertiary)' : 'var(--fg-primary)', textDecoration: it.done ? 'line-through' : 'none' }}>{it.t}</div>
              <div style={{ display: 'flex', gap: 8, marginTop: 4, alignItems: 'center' }}>
                {it.time && <span className="mono" style={{ fontSize: 11, color: it.overdue ? 'var(--danger)' : 'var(--accent-tint-fg)' }}>{it.time}</span>}
                {it.overdue && <span className="mono" style={{ fontSize: 11, color: 'var(--danger)', fontWeight: 600 }}>OVERDUE</span>}
                {it.reminder && <Icon name="bell" s={11} color="var(--fg-tertiary)" />}
                {it.location && <Icon name="location" s={11} color="var(--fg-tertiary)" />}
                {it.flagged && <Icon name="flagFill" s={11} color="var(--warn)" />}
                {it.subtree && <SubtreeBadge {...it.subtree} />}
              </div>
            </div>
          </div>
        ))}
      </div>
      <FAB />
    </div>
  );
};

// ── C. Editorial Today (iA-Writer-flavored) ─────────────────────
const EditorialToday = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54, fontFamily: 'Georgia, "Source Serif Pro", "Iowan Old Style", serif' }}>
    <div style={{ padding: '12px 28px 18px' }}>
      <div className="mono" style={{ fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 1.2, marginBottom: 4 }}>F R I · M A Y · 0 8</div>
      <div style={{ fontSize: 36, fontWeight: 400, color: 'var(--fg-primary)', letterSpacing: -0.5, fontStyle: 'italic' }}>Today</div>
    </div>
    <div style={{ flex: 1, overflow: 'auto', padding: '0 28px 90px' }}>
      <div style={{ fontFamily: 'var(--font-rounded)', fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 1.5, marginBottom: 10, marginTop: 20 }}>Morning</div>
      {[
        { t: '5km run, slow pace', time: '6:30', done: true },
        { t: 'Meditate', time: '7:00', habit: '1/1' },
        { t: 'Standup with the agentic-coding crew', time: '9:00' },
      ].map((it, i) => (
        <div key={i} style={{ display: 'flex', gap: 14, padding: '14px 0', alignItems: 'baseline' }}>
          <span className="mono" style={{ fontSize: 11, color: 'var(--accent-tint-fg)', width: 36, fontFamily: 'var(--font-mono)' }}>{it.time}</span>
          <span style={{ fontSize: 19, color: it.done ? 'var(--fg-tertiary)' : 'var(--fg-primary)', textDecoration: it.done ? 'line-through' : 'none', flex: 1, lineHeight: 1.35 }}>{it.t}</span>
          {it.habit && <span className="mono" style={{ fontSize: 11, color: 'var(--accent)', fontFamily: 'var(--font-mono)' }}>{it.habit}</span>}
        </div>
      ))}

      <div style={{ fontFamily: 'var(--font-rounded)', fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 1.5, marginBottom: 10, marginTop: 24 }}>Afternoon</div>
      {[
        { t: 'Pick up dry cleaning, Margaret & Ruthven', time: '14:30' },
        { t: 'Draft v1.0 release notes — three takes', time: '15:00', sub: '2 of 4 sections' },
        { t: 'Call Mum', time: '17:00', flag: true },
      ].map((it, i) => (
        <div key={i} style={{ display: 'flex', gap: 14, padding: '14px 0', alignItems: 'baseline', borderTop: i ? '0.5px solid var(--sep-translucent)' : 'none' }}>
          <span className="mono" style={{ fontSize: 11, color: 'var(--accent-tint-fg)', width: 36 }}>{it.time}</span>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 19, color: 'var(--fg-primary)', lineHeight: 1.35 }}>{it.t}{it.flag && ' ⚑'}</div>
            {it.sub && <div style={{ fontSize: 13, color: 'var(--fg-secondary)', fontStyle: 'italic', marginTop: 3 }}>{it.sub}</div>}
          </div>
        </div>
      ))}
    </div>
  </div>
);

Object.assign(window, { TimeSpineToday, TotStyleScreen, EditorialToday });
