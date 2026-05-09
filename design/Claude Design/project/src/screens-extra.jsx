/* Lists — Density variants + macOS view */

// Compact / Comfortable / Cozy comparison: same list, three densities side-by-side
const DensityVariant = ({ density = 'comfortable', label }) => (
  <div className={`density-${density}`} style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px' }}>
      <div style={{ fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, fontWeight: 600 }}>{label}</div>
      <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Apollo</div>
    </div>
    <div style={{ flex: 1, overflow: 'auto' }}>
      <SectionHead title="This Week" count={4} />
      <InsetCard>
        <ListRow type="task" title="Lock landing copy" due={{label:'Mon May 11'}} priority="high" subtree={{done:3,total:5}} />
        <Separator />
        <ListRow type="task" title="Record demo screencap" time="2:00 PM" reminder />
        <Separator />
        <ListRow type="note" title="Investor 1-pager · v2" body="Final sweep before Wednesday's call." />
        <Separator />
        <ListRow type="task" title="Email Sarah re: addendum" done flagged />
      </InsetCard>
      <SectionHead title="Backlog" count={3} />
      <InsetCard>
        <ListRow type="task" title="Wire pricing comparison" priority="medium" subtree={{done:0,total:3}} />
        <Separator />
        <ListRow type="task" title="Audit agent-onboarding flow" tags={['ux']} agent="claude-code" />
        <Separator />
        <ListRow type="habit" title="Weekly project review" habit={{count:3,goal:4}} recurring />
      </InsetCard>
    </div>
  </div>
);

// macOS three-pane: sidebar + list + detail
const MacOSTriple = () => (
  <div style={{ display: 'flex', height: '100%', background: 'var(--bg-grouped)', fontFamily: 'var(--font-rounded)' }}>
    {/* Sidebar */}
    <div style={{ width: 240, background: 'var(--bg-surface-2)', borderRight: '0.5px solid var(--sep-translucent)', padding: '50px 0 0', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '4px 12px 10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 30, borderRadius: 6, background: 'var(--bg-elevated)', padding: '0 10px', fontSize: 12, color: 'var(--fg-tertiary)' }}>
          <Icon name="search" s={13} /> Search
        </div>
      </div>
      <div style={{ padding: '0 8px', overflow: 'auto' }}>
        <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, padding: '8px 8px 4px' }}>Pinned</div>
        <SidebarRow icon="sun" hue="var(--hue-amber)" label="Today" count={7} active />
        <SidebarRow icon="calendar" hue="var(--hue-orange)" label="Scheduled" count={24} />
        <SidebarRow icon="flag" hue="var(--hue-pink)" label="Flagged" count={3} />
        <SidebarRow icon="bolt" hue="var(--danger)" label="Urgent" count={1} />
        <SidebarRow icon="inbox" hue="var(--accent)" label="All" count={148} />
        <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, padding: '12px 8px 4px' }}>Lists</div>
        <SidebarRow icon="list" hue="var(--hue-blue)" label="Tasks" count={12} />
        <SidebarRow icon="folder" hue="var(--hue-amber)" label="Work" count={8} />
        <SidebarRow icon="sparkle1" hue="var(--accent)" label="Project Apollo" count={5} indent={1} />
        <SidebarRow icon="home" hue="var(--hue-pink)" label="Personal" count={4} />
        <SidebarRow icon="cart" hue="var(--hue-green)" label="Groceries" count={11} presence />
        <SidebarRow icon="leaf" hue="var(--hue-teal)" label="Habits" count={6} />
        <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, padding: '12px 8px 4px' }}>AI</div>
        <SidebarRow icon="cpu" hue="var(--accent)" label="claude-code" count={3} agent="working" />
        <SidebarRow icon="cpu" hue="var(--hue-blue)" label="codex" count={1} indent={1} />
      </div>
    </div>

    {/* List column */}
    <div style={{ width: 360, background: 'var(--bg-grouped)', borderRight: '0.5px solid var(--sep-translucent)', display: 'flex', flexDirection: 'column', paddingTop: 50 }}>
      <div style={{ padding: '6px 18px 10px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <div style={{ fontSize: 11, color: 'var(--fg-tertiary)', textTransform: 'uppercase', letterSpacing: 0.6, fontWeight: 600 }}>Friday, May 8</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: 'var(--fg-primary)' }}>Today</div>
        </div>
        <Icon name="sliders" s={16} color="var(--fg-secondary)" />
      </div>
      <div style={{ flex: 1, overflow: 'auto' }}>
        <SectionHead title="Overdue" count={2} color="var(--danger)" />
        <InsetCard>
          <ListRow type="task" title="File quarterly tax submission" due={{label:'2 days ago', overdue: true}} priority="high" />
          <Separator />
          <ListRow type="task" title="Reply to Ada" due={{label:'Yesterday', overdue: true}} reminder />
        </InsetCard>
        <SectionHead title="This Morning" count={3} />
        <InsetCard>
          <ListRow type="task" title="Run 5km" time="6:30 AM" done />
          <Separator />
          <ListRow type="habit" title="Meditate" habit={{count:1,goal:1}} time="7:00 AM" recurring />
          <Separator />
          <ListRow type="task" title="Standup with the agentic-coding crew" time="9:00 AM" reminder />
        </InsetCard>
        <SectionHead title="This Afternoon" count={3} />
        <InsetCard>
          <ListRow type="task" title="Pick up dry cleaning" time="2:30 PM" location reminder tags={['errand']} />
          <Separator />
          <ListRow type="task" title="Draft v1.0 release notes" time="3:00 PM" priority="medium" subtree={{done:2,total:4}} />
          <Separator />
          <ListRow type="task" title="Call Mum" time="5:00 PM" reminder flagged />
        </InsetCard>
      </div>
    </div>

    {/* Detail column */}
    <div style={{ flex: 1, background: 'var(--bg-base)', padding: '50px 32px 0', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div className="mono" style={{ fontSize: 10, color: 'var(--fg-tertiary)', letterSpacing: 0 }}>uuid:a3f7b2c1 · modified 2m ago</div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', color: 'var(--fg-secondary)' }}>
          <Icon name="flag" s={15}/><Icon name="bolt" s={15}/><Icon name="moreH" s={15}/>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <Checkbox /><div style={{ flex: 1 }}>
          <div style={{ fontSize: 26, fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.3, lineHeight: 1.2 }}>Draft v1.0 release notes</div>
          <div style={{ display: 'flex', gap: 8, marginTop: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <span className="mono" style={{ fontSize: 12, color: 'var(--accent-tint-fg)' }}>Today · 3:00 PM</span>
            <Icon name="bell" s={12} color="var(--fg-tertiary)" />
            <Priority level="medium" />
            <SubtreeBadge done={2} total={4} />
            <Tag label="copy" /><Tag label="launch" />
          </div>
        </div>
      </div>
      <div style={{ marginTop: 22, fontSize: 14, color: 'var(--fg-primary)', lineHeight: 1.55 }}>
        Three takes for the headline. Lead with the data-ownership angle. Reference Apollo's API stability score from Q1 deck.
        <br/><br/>
        Sections to cover:
      </div>
      <div style={{ marginTop: 16, padding: 14, borderRadius: 12, background: 'var(--bg-grouped)', display: 'flex', flexDirection: 'column', gap: 4 }}>
        <SubItem done title="Hero copy · 3 directions" />
        <SubItem done title="Quote from Sarah's interview" />
        <SubItem title="Pricing block (defer to v2?)" />
        <SubItem title="CTA microcopy A/B" />
      </div>
      <div style={{ marginTop: 18, padding: '10px 14px', background: 'var(--accent-soft)', borderRadius: 10, display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--accent-tint-fg)' }}>
        <Icon name="cpu" s={14} color="var(--accent)" /> claude-code drafted 2 sub-items · review when ready
      </div>
    </div>
  </div>
);

const SubItem = ({ done, title }) => (
  <div style={{ display: 'flex', gap: 10, padding: '6px 0', alignItems: 'center' }}>
    <Checkbox checked={done} size={18} />
    <span style={{ fontSize: 14, color: done ? 'var(--fg-tertiary)' : 'var(--fg-primary)', textDecoration: done ? 'line-through' : 'none' }}>{title}</span>
  </div>
);

Object.assign(window, { DensityVariant, MacOSTriple });
