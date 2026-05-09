/* Lists — Mobile screens (iPhone Tier 1)
 * Sidebar, Today, ListVertical, ListColumn, ItemSheet, HabitDetail.
 * Uses primitives.jsx components.
 */

// ── Filled smart row — full-width colored bar (Favorites) ───────
const SmartRowFilled = ({ icon, hue, label, count, active, hideCount }) => (
  <div style={{
    background: hue, color: '#fff',
    margin: '0 16px 10px', borderRadius: 12,
    padding: '14px 16px', minHeight: 56,
    display: 'flex', alignItems: 'center', gap: 14,
  }}>
    <Icon name={icon} s={20} color="#fff" strokeWidth={2.1} />
    <div style={{ flex: 1, fontSize: 16, fontWeight: 700, letterSpacing: -0.1 }}>{label}</div>
    {!hideCount && (
      <span className="mono" style={{ fontSize: 19, fontWeight: 700, lineHeight: 1, letterSpacing: -0.3, color: '#fff' }}>{count}</span>
    )}
  </div>
);

// ── Sidebar / home view ─────────────────────────────────────────
const SidebarScreen = ({ tab = 'lists', dark = false }) => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    {/* large title + toolbar (search lives in the toolbar) */}
    <div style={{ padding: '6px 16px 8px', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
      <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Lists</div>
      <div style={{ display: 'flex', gap: 6 }}>
        <CircleBtn icon="search" />
        <CircleBtn icon="moreH" />
      </div>
    </div>

    <div style={{ flex: 1, overflow: 'auto', padding: '10px 0' }}>
      {/* FAVORITES — full-width colored rows */}
      <SmartRowFilled icon="sun" hue="var(--hue-amber)" label="Today" count={7} active />
      <SmartRowFilled icon="calendar" hue="var(--hue-orange)" label="Scheduled" count={24} />
      <SmartRowFilled icon="flag" hue="var(--hue-pink)" label="Flagged" count={3} />
      <SmartRowFilled icon="bolt" hue="var(--danger)" label="Urgent" count={1} />
      <SmartRowFilled icon="check" hue="var(--hue-grey)" label="Completed" count={112} hideCount />
      <SmartRowFilled icon="inbox" hue="var(--accent)" label="All" count={148} />

      {/* MY LISTS */}
      <SectionHeaderWithAdd label="My Lists" />
      <InsetCard>
        <SidebarRow icon="list" hue="var(--hue-blue)" label="Tasks" count={12} />
        <Separator/>
        <SidebarRow icon="folder" hue="var(--hue-amber)" label="Work" count={8} />
        <Separator inset={70} />
        <SidebarRow icon="sparkle1" hue="var(--accent)" label="Project Apollo" count={5} indent={1} />
        <Separator inset={70} />
        <SidebarRow icon="book" hue="var(--hue-purple)" label="Reading" count={3} indent={1} />
        <Separator/>
        <SidebarRow icon="home" hue="var(--hue-pink)" label="Personal" count={4} />
        <Separator/>
        <SidebarRow icon="cart" hue="var(--hue-green)" label="Groceries" count={11} presence />
        <Separator/>
        <SidebarRow icon="leaf" hue="var(--hue-teal)" label="Habits" count={6} />
        <Separator/>
        <SidebarRow icon="cpu" hue="var(--hue-purple)" label="Claude Code" count={2} agent="agent" />
      </InsetCard>

      <SectionHeaderWithAdd label="System" />
      <InsetCard>
        <SidebarRow icon="tag" hue="var(--hue-grey)" label="Tags" count={14} />
        <Separator/>
        <SidebarRow icon="trash" hue="var(--hue-grey)" label="Recently Deleted" count={6} />
      </InsetCard>

      <div style={{ height: 40 }} />
    </div>
  </div>
);

// Sidebar section header with an inline "+" affordance on the right.
// Title Case label with a hairline divider above.
const SectionHeaderWithAdd = ({ label, hideDivider = false }) => (
  <>
    {!hideDivider && (
      <div style={{ height: 0.5, background: 'var(--sep-translucent)', margin: '14px 16px 0', transform: 'scaleY(0.5)', transformOrigin: 'top' }} />
    )}
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '12px 16px 6px',
    }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--fg-secondary)', letterSpacing: 0 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'center', color: 'var(--accent)' }}>
        <Icon name="plus" s={16} color="var(--accent)" strokeWidth={2.1} />
      </div>
    </div>
  </>
);

const SmartCard = ({ icon, hue, label, count, active }) => (
  <div style={{
    background: active ? 'var(--accent-soft)' : 'var(--bg-elevated)',
    borderRadius: 14, padding: 12,
    boxShadow: active ? 'inset 0 0 0 1px var(--accent-soft)' : '0 1px 0 var(--sep-opaque) inset',
    display: 'flex', flexDirection: 'column', gap: 4,
    minHeight: 86, position: 'relative',
  }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
      <div style={{ width: 30, height: 30, borderRadius: 15, background: hue, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} s={17} color="#fff" strokeWidth={2.1}/>
      </div>
      <span className="mono" style={{ fontSize: 22, fontWeight: 700, color: active ? 'var(--accent-tint-fg)' : 'var(--fg-primary)', letterSpacing: 0, lineHeight: 1 }}>{count}</span>
    </div>
    <div style={{ fontSize: 14, fontWeight: 600, color: active ? 'var(--accent-tint-fg)' : 'var(--fg-secondary)', marginTop: 'auto' }}>{label}</div>
  </div>
);

// ── Today smart list ────────────────────────────────────────────
const TodayScreen = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
      <div>
        <div style={{ fontSize: 13, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 600 }}>Friday, May 8</div>
        <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4, lineHeight: 1.1, marginTop: 2 }}>Today</div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <CircleBtn icon="search" />
        <CircleBtn icon="moreH" />
      </div>
    </div>

    <div style={{ flex: 1, overflow: 'auto', paddingBottom: 90 }}>
      <SectionHead title="Overdue" count={2} collapsed={false} color="var(--danger)" hideDivider />
      <InsetCard>
        <ListRow type="task" title="File quarterly tax submission"
          due={{ label: 'Wed · 2 days ago', overdue: true }}
          priority="high" tags={['admin']} reminder='silent' />
        <Separator />
        <ListRow type="task" title="Reply to Ada about the venue"
          due={{ label: 'Yesterday, 5:00 PM', overdue: true }} reminder />
      </InsetCard>

      <SectionHead title="All-Day" count={2} />
      <InsetCard>
        <ListRow type="habit" title="Drink water"
          habit={{ count: 5, goal: 8 }} recurring />
        <Separator />
        <ListRow type="note" title="Meeting notes — design review"
          body="Sage works. Review heatmap variants tomorrow." />
      </InsetCard>

      <SectionHead title="Morning" count={3} />
      <InsetCard>
        <ListRow type="task" title="Run 5km" time="6:30 AM" done />
        <Separator />
        <ListRow type="habit" title="Meditate"
          habit={{ count: 1, goal: 1 }} time="7:00 AM" recurring />
        <Separator />
        <ListRow type="task" title="Standup with the agentic-coding crew"
          time="9:00 AM" reminder location />
      </InsetCard>

      <SectionHead title="Afternoon" count={3} />
      <InsetCard>
        <ListRow type="task" title="Pick up dry cleaning"
          time="2:30 PM" body="Cnr Margaret & Ruthven · open until 5:30"
          location reminder tags={['errand']} />
        <Separator />
        <ListRow type="task" title="Draft v1.0 release notes"
          time="3:00 PM" priority="medium"
          subtree={{ done: 2, total: 4 }} />
        <Separator />
        <ListRow type="task" title="Call Mum" time="5:00 PM"
          reminder flagged />
      </InsetCard>

      <SectionHead title="Evening" count={2} />
      <InsetCard>
        <ListRow type="task" title="Pack for Saturday's trip"
          time="7:30 PM" tags={['travel']} />
        <Separator />
        <ListRow type="habit" title="Read · 30 min"
          habit={{ count: 0, goal: 1 }} time="9:00 PM" recurring />
      </InsetCard>
    </div>

    <FAB />
  </div>
);

const CircleBtn = ({ icon }) => (
  <div style={{
    width: 34, height: 34, borderRadius: 17,
    background: 'var(--bg-surface-2)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    color: 'var(--accent)',
  }}>
    <Icon name={icon} s={icon === 'moreH' ? 18 : 16} color="var(--accent)" />
  </div>
);

// ── Today empty state ───────────────────────────────────────────
const TodayEmpty = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px' }}>
      <div style={{ fontSize: 13, color: 'var(--fg-secondary)', textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 600 }}>Friday, May 8</div>
      <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Today</div>
    </div>
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 40, gap: 16, textAlign: 'center' }}>
      <div style={{
        width: 76, height: 76, borderRadius: 38,
        background: 'var(--accent-soft)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icon name="sun" s={40} color="var(--accent)" strokeWidth={1.6} />
      </div>
      <div>
        <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--fg-primary)', marginBottom: 4 }}>Nothing scheduled</div>
        <div style={{ fontSize: 14, color: 'var(--fg-secondary)', lineHeight: 1.4, maxWidth: 240 }}>Today is open. Pull down to add a quick task or check Scheduled.</div>
      </div>
      <div style={{
        marginTop: 8, padding: '10px 18px',
        borderRadius: 999, background: 'var(--accent-soft)',
        color: 'var(--accent-tint-fg)', fontSize: 14, fontWeight: 600,
        display: 'flex', alignItems: 'center', gap: 6,
      }}>
        <Icon name="plus" s={14} color="var(--accent-tint-fg)" /> Quick add
      </div>
    </div>
    <FAB />
  </div>
);

// ── List view (vertical) — Project Apollo ───────────────────────
const ListVertical = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
      <div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', color: 'var(--accent)', fontSize: 15, fontWeight: 500, marginBottom: 4 }}>
          <Icon name="chevronR" s={11} color="var(--accent)" style={{ transform: 'scaleX(-1)' }} /> Work
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <div style={{ width: 32, height: 32, borderRadius: 16, background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="sparkle1" s={18} color="#fff" />
          </div>
          <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Apollo</div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <CircleBtn icon="sliders" />
        <CircleBtn icon="moreH" />
      </div>
    </div>

    <div style={{ flex: 1, overflow: 'auto', paddingBottom: 90 }}>
      <SectionHead title="This Week" count={4} hideDivider />
      <InsetCard>
        <ListRow type="task" title="Lock down the launch landing copy"
          due={{ label: 'Mon May 11' }} priority="high"
          subtree={{ done: 3, total: 5 }} tags={['copy']} />
        <Separator />
        <ListRow type="task" title="Record demo screencap"
          due={{ label: 'Tue May 12' }} reminder time="2:00 PM" />
        <Separator />
        <ListRow type="note" title="Investor 1-pager · v2"
          body="Final sweep before Wednesday's call. Pull metrics from Q1 deck."
          tags={['decks']} />
        <Separator />
        <ListRow type="task" title="Email Sarah about the contract addendum"
          done flagged />
      </InsetCard>

      <SectionHead title="Backlog" count={5} />
      <InsetCard>
        <ListRow type="task" title="Wire up the pricing comparison table"
          priority="medium" subtree={{ done: 0, total: 3 }} />
        <Separator />
        <ListRow type="task" title="Audit the agent-onboarding flow"
          tags={['ux','agents']} agent="claude-code" />
        <Separator />
        <ListRow type="task" title="Migrate analytics events to v2 schema"
          tags={['eng']} priority="low" />
        <Separator />
        <ListRow type="habit" title="Weekly project review"
          habit={{ count: 3, goal: 4 }} recurring />
        <Separator />
        <ListRow type="note" title="Naming candidates · longlist"
          body="Threaded with Saxon — narrow to 5 by Friday."
          subtree={{ done: 2, total: 8 }} />
      </InsetCard>
    </div>

    <FAB />
  </div>
);

// ── Grocery mode ────────────────────────────────────────────────
const GroceryScreen = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
      <div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', color: 'var(--accent)', fontSize: 15, fontWeight: 500, marginBottom: 4 }}>
          <Icon name="chevronR" s={11} color="var(--accent)" style={{ transform: 'scaleX(-1)' }} /> Lists
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <div style={{ width: 32, height: 32, borderRadius: 16, background: 'var(--hue-green)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="cart" s={18} color="#fff" />
          </div>
          <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Groceries</div>
        </div>
        <div style={{ marginTop: 6, fontSize: 12, color: 'var(--fg-tertiary)', display: 'flex', gap: 6, alignItems: 'center' }}>
          <Icon name="sparkles" s={11} color="var(--fg-tertiary)" /> Auto-categorized
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <CircleBtn icon="sliders" />
        <CircleBtn icon="moreH" />
      </div>
    </div>

    <div style={{ flex: 1, overflow: 'auto', paddingBottom: 90 }}>
      <SectionHead title="Produce" count={4} hideDivider />
      <InsetCard>
        <ListRow type="task" title="Spinach (one bag)" />
        <Separator />
        <ListRow type="task" title="Avocado (3)" />
        <Separator />
        <ListRow type="task" title="Lemons" done />
        <Separator />
        <ListRow type="task" title="Cherry tomatoes" />
      </InsetCard>
      <SectionHead title="Dairy" count={2} />
      <InsetCard>
        <ListRow type="task" title="Oat milk" />
        <Separator />
        <ListRow type="task" title="Greek yogurt · 1kg" />
      </InsetCard>
      <SectionHead title="Bakery" count={1} />
      <InsetCard>
        <ListRow type="task" title="Sourdough loaf" />
      </InsetCard>
      <SectionHead title="Pantry" count={3} />
      <InsetCard>
        <ListRow type="task" title="Brown rice (2kg)" done />
        <Separator />
        <ListRow type="task" title="Tinned tomatoes (4)" />
        <Separator />
        <ListRow type="task" title="Chickpeas (2 cans)" />
      </InsetCard>
    </div>

    <FAB />
  </div>
);

// ── List view (column / kanban) ─────────────────────────────────
const ListColumn = () => (
  <div style={{ background: 'var(--bg-grouped)', height: '100%', display: 'flex', flexDirection: 'column', paddingTop: 54 }}>
    <div style={{ padding: '4px 16px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
      <div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', color: 'var(--accent)', fontSize: 15, fontWeight: 500, marginBottom: 4 }}>
          <Icon name="chevronR" s={11} color="var(--accent)" style={{ transform: 'scaleX(-1)' }} /> Work
        </div>
        <div style={{ fontSize: 'var(--t-largeTitle)', fontWeight: 700, color: 'var(--fg-primary)', letterSpacing: -0.4 }}>Apollo</div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <CircleBtn icon="sliders" />
        <CircleBtn icon="moreH" />
      </div>
    </div>

    <div style={{ flex: 1, display: 'flex', overflowX: 'auto', overflowY: 'hidden', gap: 12, padding: '8px 16px 90px', scrollSnapType: 'x mandatory' }}>
      {[
        { name: 'To do', count: 3, hue: 'var(--hue-grey)', items: [
          { title: 'Lock landing copy', due: 'Mon May 11', priority: 'high', tags: ['copy'] },
          { title: 'Wire pricing table', priority: 'medium', subtree: {done:0,total:3} },
          { title: 'Audit agent flow', tags: ['ux'], agent: 'claude-code' },
        ]},
        { name: 'In progress', count: 2, hue: 'var(--accent)', items: [
          { title: 'Record demo screencap', due: 'Tue May 12', reminder: true, time: '2:00 PM' },
          { title: 'Investor 1-pager v2', body: 'Final sweep before Wed', tags: ['decks'] },
        ]},
        { name: 'Done', count: 4, hue: 'var(--hue-green)', items: [
          { title: 'Email Sarah re: addendum', done: true },
          { title: 'Sketch hero animation', done: true },
        ]},
      ].map(col => (
        <div key={col.name} style={{
          flex: '0 0 auto', width: 280, scrollSnapAlign: 'start',
          background: 'var(--bg-elevated)', borderRadius: 14, padding: 10,
          display: 'flex', flexDirection: 'column', gap: 8,
          boxShadow: '0 1px 0 var(--sep-opaque) inset',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 6px' }}>
            <div style={{ width: 8, height: 8, borderRadius: 4, background: col.hue }} />
            <div style={{ fontSize: 14, fontWeight: 700, color: 'var(--fg-primary)', flex: 1 }}>{col.name}</div>
            <span className="mono" style={{ fontSize: 12, color: 'var(--fg-tertiary)' }}>{col.count}</span>
            <Icon name="plus" s={15} color="var(--fg-tertiary)" />
          </div>
          {col.items.map((it, i) => (
            <div key={i} style={{
              background: 'var(--bg-grouped)', borderRadius: 10, padding: '10px 12px',
              boxShadow: 'inset 0 0 0 0.5px var(--sep-opaque)',
            }}>
              <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                <Checkbox checked={it.done} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, color: it.done ? 'var(--fg-tertiary)' : 'var(--fg-primary)', textDecoration: it.done ? 'line-through' : 'none', lineHeight: 1.3 }}>
                    {it.title}
                    {it.priority && <span style={{ marginLeft: 6, display: 'inline-block', verticalAlign: 'middle' }}><Priority level={it.priority} /></span>}
                  </div>
                  {it.body && <div style={{ fontSize: 12, color: 'var(--fg-secondary)', marginTop: 2 }}>{it.body}</div>}
                  <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginTop: 6, flexWrap: 'wrap' }}>
                    {it.due && <span className="mono" style={{ fontSize: 11, color: 'var(--accent-tint-fg)' }}>{it.due}</span>}
                    {it.time && <span className="mono" style={{ fontSize: 11, color: 'var(--fg-secondary)' }}>{it.time}</span>}
                    {it.reminder && <Icon name="bell" s={11} color="var(--fg-tertiary)" />}
                    {it.subtree && <SubtreeBadge {...it.subtree} />}
                    {(it.tags||[]).map(t => <Tag key={t} label={t} />)}
                    {it.agent && <span className="mono" style={{ fontSize: 10, color: 'var(--accent-tint-fg)', fontWeight: 600, padding: '1px 5px', borderRadius: 4, background: 'var(--accent-soft)' }}>{it.agent}</span>}
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
    <FAB />
  </div>
);

Object.assign(window, { SidebarScreen, TodayScreen, TodayEmpty, ListVertical, GroceryScreen, ListColumn, SmartCard, CircleBtn });
