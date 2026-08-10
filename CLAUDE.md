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
- `.subnav` (subtabs), `.scopebar` (gemeente/focus/peiljaar/niveau) and `.view-params-bar`
  (indicator + absoluut/relatief — only rendered for the Kaart and Ontwikkeling over tijd views)
  are wrapped together in `.frozen-bar`, sticky under the topbar, **in that top-to-bottom order**.
  `.subnav` deliberately shares its background with `.content-shell`/`.main` (plain `--surface-1`)
  so it reads as navigation; `.scopebar` and `.view-params-bar` share a tinted background
  (`color-mix(... var(--surface-2) ... var(--brand) ...)`) so the two parameter rows read as one
  distinct block, visually separate from both the tab navigation above and the chart/card area
  below. Don't reuse `.filterbar`'s padding on `.scopebar`/`.view-params-bar` — `.filterbar` is for
  per-view local control rows inside `<main>` (top-heavy padding, no bottom), and relying on CSS
  cascade order between the two classes previously caused a padding bug (bottom-aligned controls).
- `.content-shell` wraps the frozen bar + `<main>` in a max-width column with its own background/
  border so the column reads as distinct from the page margins on wide screens — keep new
  full-width chrome (banners, toolbars) inside it rather than breaking out to the viewport edge.
