/* Lists — Design system viewer
 * Color, type, icons, spacing, motion. Compact display for design canvas.
 */

const Swatch = ({ name, value, label, mono }) => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 72 }}>
    <div style={{
      width: 72, height: 56, borderRadius: 10,
      background: `var(${value})`,
      boxShadow: 'inset 0 0 0 0.5px var(--sep-opaque)',
    }} />
    <div>
      <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--fg-primary)', lineHeight: 1.3 }}>{name}</div>
      <div className="mono" style={{ fontSize: 9.5, color: 'var(--fg-tertiary)', letterSpacing: 0 }}>{value.replace('--', '')}</div>
    </div>
  </div>
);

const ColorPalette = () => (
  <div style={{ padding: 24, height: '100%', overflow: 'auto' }}>
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>Sage Accent</div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Swatch name="Accent" value="--accent" />
        <Swatch name="Soft" value="--accent-soft" />
        <Swatch name="Press" value="--accent-press" />
        <Swatch name="Tint bg" value="--accent-tint-bg" />
      </div>
    </div>
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>Surfaces</div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Swatch name="Grouped" value="--bg-grouped" />
        <Swatch name="Base" value="--bg-base" />
        <Swatch name="Elevated" value="--bg-elevated" />
        <Swatch name="Surface 2" value="--bg-surface-2" />
        <Swatch name="Tinted" value="--bg-tinted" />
      </div>
    </div>
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>Text</div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Swatch name="Primary" value="--fg-primary" />
        <Swatch name="Secondary" value="--fg-secondary" />
        <Swatch name="Tertiary" value="--fg-tertiary" />
        <Swatch name="Quaternary" value="--fg-quaternary" />
      </div>
    </div>
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>Semantic</div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Swatch name="Success" value="--success" />
        <Swatch name="Warn" value="--warn" />
        <Swatch name="Danger" value="--danger" />
        <Swatch name="Info" value="--info" />
      </div>
    </div>
    <div>
      <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>List Hues</div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        {['blue','teal','green','amber','orange','pink','purple','grey'].map(h => (
          <Swatch key={h} name={h[0].toUpperCase()+h.slice(1)} value={`--hue-${h}`} />
        ))}
      </div>
    </div>
  </div>
);

const TypeScale = () => {
  const rows = [
    { name: 'Large Title',  size: 'var(--t-largeTitle)', weight: 700, sample: 'Today' },
    { name: 'Title 1',      size: 'var(--t-title1)',     weight: 700, sample: 'Project Apollo' },
    { name: 'Title 2',      size: 'var(--t-title2)',     weight: 700, sample: 'This Week' },
    { name: 'Title 3',      size: 'var(--t-title3)',     weight: 600, sample: 'Section header' },
    { name: 'Headline',     size: 'var(--t-headline)',   weight: 600, sample: 'Buy oat milk and bread' },
    { name: 'Body',         size: 'var(--t-body)',       weight: 400, sample: 'Buy oat milk and bread' },
    { name: 'Callout',      size: 'var(--t-callout)',    weight: 400, sample: 'Today, 5:00 PM · 15 min before' },
    { name: 'Subheadline',  size: 'var(--t-subheadline)',weight: 400, sample: 'Today, 5:00 PM · 15 min before' },
    { name: 'Footnote',     size: 'var(--t-footnote)',   weight: 400, sample: 'Toowoomba · 200m radius' },
    { name: 'Caption',      size: 'var(--t-caption1)',   weight: 400, sample: 'Edited 2 minutes ago' },
  ];
  return (
    <div style={{ padding: 24, height: '100%', overflow: 'auto' }}>
      <div style={{ marginBottom: 16 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 4 }}>Family</div>
        <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--fg-primary)' }}>SF Pro Rounded</div>
        <div className="mono" style={{ fontSize: 12, color: 'var(--fg-tertiary)' }}>ui-rounded → Nunito fallback · SF Mono → JetBrains Mono</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        {rows.map(r => (
          <div key={r.name} style={{ display: 'flex', alignItems: 'baseline', gap: 14, paddingBottom: 12, borderBottom: '0.5px solid var(--sep-translucent)' }}>
            <div style={{ width: 100, flexShrink: 0 }}>
              <div className="mono" style={{ fontSize: 10, color: 'var(--fg-tertiary)' }}>{r.size.replace('var(--t-','').replace(')','')}</div>
              <div style={{ fontSize: 12, color: 'var(--fg-secondary)', fontWeight: 500 }}>{r.name}</div>
            </div>
            <div style={{ fontSize: r.size, fontWeight: r.weight, lineHeight: 1.2, color: 'var(--fg-primary)' }}>{r.sample}</div>
          </div>
        ))}
        <div style={{ marginTop: 8 }}>
          <div className="mono" style={{ fontSize: 'var(--t-footnote)', color: 'var(--fg-secondary)' }}>SF Mono · #groceries · 2026-05-08T17:00 · uuid:a3f7b2c1</div>
        </div>
      </div>
    </div>
  );
};

const IconGrid = () => {
  const groups = [
    { title: 'Smart lists', items: ['sun','calendar','flag','bolt','check','inbox'] },
    { title: 'Item types', items: ['bullet','repeat','document'] },
    { title: 'Lists', items: ['list','folder','cart','book','code','leaf','home','sparkle1'] },
    { title: 'Metadata', items: ['bell','bellSlash','clock','location','tag','flame','pin'] },
    { title: 'Actions', items: ['plus','search','sliders','moreH','grip','trash','arrowR'] },
    { title: 'Agents', items: ['cpu','sparkles','siri'] },
  ];
  return (
    <div style={{ padding: 24, height: '100%', overflow: 'auto' }}>
      {groups.map(g => (
        <div key={g.title} style={{ marginBottom: 18 }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 10 }}>{g.title}</div>
          <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
            {g.items.map(name => (
              <div key={name} style={{ width: 64, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                <div style={{
                  width: 44, height: 44, borderRadius: 10,
                  background: 'var(--bg-elevated)',
                  boxShadow: 'inset 0 0 0 0.5px var(--sep-opaque)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: 'var(--fg-primary)',
                }}>
                  <Icon name={name} s={22} color="var(--accent)" />
                </div>
                <div className="mono" style={{ fontSize: 9.5, color: 'var(--fg-tertiary)', letterSpacing: 0, textAlign: 'center' }}>{name}</div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
};

const SpacingScale = () => {
  const steps = [
    { name: '1', val: 4 }, { name: '2', val: 8 }, { name: '3', val: 12 },
    { name: '4', val: 16 }, { name: '5', val: 20 }, { name: '6', val: 24 },
    { name: '7', val: 32 }, { name: '8', val: 40 }, { name: '9', val: 48 },
  ];
  const radii = [
    { name: 'sm', val: 6 }, { name: 'md', val: 10 }, { name: 'lg', val: 14 },
    { name: 'xl', val: 20 }, { name: 'card', val: 16 }, { name: 'pill', val: 999 },
  ];
  return (
    <div style={{ padding: 24, height: '100%', overflow: 'auto' }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 12 }}>Spacing · 4pt grid</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 24 }}>
        {steps.map(s => (
          <div key={s.name} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div className="mono" style={{ width: 24, fontSize: 11, color: 'var(--fg-secondary)' }}>s-{s.name}</div>
            <div style={{ height: 12, width: s.val, background: 'var(--accent)', borderRadius: 2 }} />
            <div className="mono" style={{ fontSize: 10, color: 'var(--fg-tertiary)' }}>{s.val}px</div>
          </div>
        ))}
      </div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 12 }}>Radii</div>
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginBottom: 24 }}>
        {radii.map(r => (
          <div key={r.name} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
            <div style={{
              width: 44, height: 44, background: 'var(--accent-soft)',
              borderRadius: r.val, boxShadow: 'inset 0 0 0 1px var(--accent)',
            }} />
            <div className="mono" style={{ fontSize: 10, color: 'var(--fg-secondary)' }}>{r.name}</div>
          </div>
        ))}
      </div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 12 }}>Shadow</div>
      <div style={{ display: 'flex', gap: 16 }}>
        <div style={{ width: 80, height: 60, background: 'var(--bg-elevated)', borderRadius: 12, boxShadow: 'var(--shadow-pop)' }} />
        <div style={{ width: 80, height: 60, background: 'var(--bg-elevated)', borderRadius: 12, boxShadow: 'var(--shadow-sheet)' }} />
      </div>
    </div>
  );
};

const MotionScale = () => {
  const items = [
    { name: 'Quick',    val: '160ms', use: 'micro feedback (checkbox tick, tap)' },
    { name: 'Base',     val: '220ms', use: 'sheet present, list reorder' },
    { name: 'Slow',     val: '320ms', use: 'tab transitions, mode switches' },
  ];
  return (
    <div style={{ padding: 24, height: '100%', overflow: 'auto' }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 12 }}>Duration</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 24 }}>
        {items.map(s => (
          <div key={s.name} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 60, fontSize: 13, fontWeight: 600, color: 'var(--fg-primary)' }}>{s.name}</div>
            <div className="mono" style={{ width: 56, fontSize: 11, color: 'var(--accent-tint-fg)' }}>{s.val}</div>
            <div style={{ fontSize: 12, color: 'var(--fg-secondary)', flex: 1 }}>{s.use}</div>
          </div>
        ))}
      </div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 12 }}>Easing</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div className="mono" style={{ fontSize: 11, color: 'var(--fg-secondary)' }}>standard · cubic-bezier(.2,.7,.3,1)</div>
        <div className="mono" style={{ fontSize: 11, color: 'var(--fg-secondary)' }}>decel · cubic-bezier(0,0,.2,1)</div>
      </div>
      <div style={{ marginTop: 24, padding: 16, borderRadius: 10, background: 'var(--bg-surface-2)' }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 6 }}>Reduce-motion</div>
        <div style={{ fontSize: 12, color: 'var(--fg-secondary)', lineHeight: 1.5 }}>
          All transitions cut to <strong>opacity-only</strong> at 120ms. No translate, no scale, no spring. Live-presence pulse is replaced by a static dot.
        </div>
      </div>
    </div>
  );
};

const ComponentSampler = () => (
  <div style={{ padding: 24, height: '100%', overflow: 'auto', display: 'flex', flexDirection: 'column', gap: 24 }}>
    <div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8 }}>Checkbox states</div>
      <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
        <Checkbox /><Checkbox checked /><Checkbox partial />
        <HabitRing count={3} goal={8} />
        <HabitRing count={8} goal={8} />
        <Icon name="document" s={20} color="var(--fg-tertiary)" />
      </div>
    </div>
    <div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8 }}>Tags & priority</div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <Tag label="groceries" /><Tag label="work-projecta" />
        <Priority level="low" /><Priority level="medium" /><Priority level="high" />
        <SubtreeBadge done={3} total={5} />
        <SubtreeBadge done={5} total={5} complete />
      </div>
    </div>
    <div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8 }}>List icon hues</div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        {['blue','teal','green','amber','orange','pink','purple','grey'].map((h, i) => (
          <IconBadge key={h} icon={['list','folder','cart','book','code','leaf','home','flag'][i]} hue={`var(--hue-${h})`} s={32} glyph={16} />
        ))}
      </div>
    </div>
    <div>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8 }}>Indicators</div>
      <div style={{ display: 'flex', gap: 14, alignItems: 'center', color: 'var(--fg-secondary)' }}>
        <Icon name="bell" s={16} /><Icon name="bellSlash" s={16} /><Icon name="repeat" s={16} />
        <Icon name="location" s={16} /><Icon name="bolt" s={16} color="var(--danger)" />
        <Icon name="flagFill" s={16} color="var(--warn)" />
      </div>
    </div>
  </div>
);

Object.assign(window, { ColorPalette, TypeScale, IconGrid, SpacingScale, MotionScale, ComponentSampler });
