# Dynamo Amsterdam Oost — project notes for Claude

## Dashboard SPA (`dashboard_client/dashboard`)

- Single global stylesheet (`src/styles/app.css` + `src/styles/theme.css`), no CSS modules/Tailwind.
  Reuse existing classes/components rather than forking per-tab variants.
- The top nav (`App.tsx`, `NAV_GROUPS`) has two layers: a group-level nav (`.nav`) and, when a
  group has more than one view, a second-layer tab bar (`.subnav`/`.subnav-track`/
  `.subnav-indicator`) plus, for "Verkennen & Analyse", a shared parameter bar (`.scopebar`).
  **The `.subnav` styling is shared across every nav group** (currently "Verkennen & Analyse" and
  "Verantwoording & Bronnen") — it must stay one implementation. Don't add group-specific subnav
  styling; if a group needs different behavior, extend the shared component/CSS with a prop or
  modifier class instead of duplicating markup.
- `.scopebar` (parameters) and `.subnav` (subtabs) are wrapped together in `.frozen-bar`, which is
  sticky under the topbar and uses one shared tinted background (`color-mix(... var(--surface-2)
  ... var(--brand) ...)`) so both rows read as one frozen toolbar, distinct from the
  `.content-shell` (chart/card area) background beneath them.
- `.content-shell` wraps the frozen bar + `<main>` in a max-width column with its own background/
  border so the column reads as distinct from the page margins on wide screens — keep new
  full-width chrome (banners, toolbars) inside it rather than breaking out to the viewport edge.
