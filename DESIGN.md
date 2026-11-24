---
colors:                 # this project's palette: its own decision, no shared default
  # Greys from the system-colour starter, plus ONE hue: purple accent (2026-11-12, OneNote's
  # colour). Raw palette --purple-* in tokens.css; roles point at it.
  bg: "Canvas"
  surface: "Canvas"
  ink: "CanvasText"          # text on bg/surface >= 4.5:1
  muted: "CanvasText 72%"    # >= 4.5:1 for text, 3:1 for icons
  border: "CanvasText 14%"   # dividers
  border-strong: "CanvasText 50%" # field and button edges >= 3:1
  accent: "#6D28D9"          # light; dark theme #A78BFA
  accent-hover: "#5B21B6"    # light; dark theme #C4B5FD
  on-accent: "#FFFFFF"       # light (7.1:1); dark theme #141414 on #A78BFA (6.8:1)
  ring: "{colors.accent}"
  danger: "CanvasText"       # no hue; the icon and the word carry the meaning
typography:
  ui: "Inter, system-ui, sans-serif"
  mono: "'JetBrains Mono', ui-monospace, monospace"
  scale: [10, 11, 12, 13, 14, 16, 20]
rounded: { sm: 4, md: 6, lg: 8 }
spacing: [2, 4, 6, 8, 12, 16, 24, 32]
components:
  button: { height: 32, coarse-height: 44, radius: "{rounded.md}", background: "{colors.accent}" }
  input:  { height: 32, radius: "{rounded.sm}", border: "{colors.border}" }
---

# Design — ObsidiNote

## Overview
Creative North Star: **"Quiet Atlas"**. A calm reading surface in greys with one purple accent, OneNote's colour. Purple says "this is the thing to act on or the thing you picked"; everything else is grey. In the map, structure (grey cluster areas, dot size, line weight) carries the meaning; purple appears only on the focused dot and its links.

Tokens live in `src/styles/tokens.css` (copied from CommonShared `templates/tokens.css`).
No hard-coded colours or sizes in components.

## Named Rules
- **The Colour Is Content Rule** — accent marks action, focus, selection; never decoration.
- **Flat-By-Default** — shadows only on floating layers (menus, dialogs, popovers).
- **Paired-Signal** — every status colour comes with text or an icon.
- **Weight Is Relevance** — in the map, link strength is line weight and opacity, and dot size is the link weight of the page (strengths of the links to it plus half of its own, one smooth scale; hubs get a thicker outline, not a size jump); clusters are grey areas, labelled by topic. Links between two topics are one soft line from area to area whose width is the summed strength of their links, bent around any third topic in its way through the middle of the gaps (and drawn under the solid areas), so it never lies across or under a third topic; topics with links between them are placed next to each other (strongest first), so a line rarely needs to bend; at rest only the 8 heaviest, all of them from 1.5x the fitted zoom, all of a topic's when one of its pages is focused; ends on the facing side, spread along the rim (the page-to-page lines appear for the focused page only). A topic name sits bold in the middle of its own area, in room the layout keeps free of dots (`labelSize.ts` labelSlot; review 2026-11-14: names lay on 1 to 5 of their own dots), sized for the zoom the map is fitted to (a map of a few hundred pages is fitted zoomed out, where a name covers more of it; `layout.ts` layoutGraph lays out again with that much more room), and fades out while the pointer is over that area or one of its pages is focused. The count of the area's pages drawn sits beside the name, small and muted, inside that same room. Pointing at a page (or searching) lays one veil in the stage colour over the whole map, areas and names included (`--kg-veil`), and draws the page, its linked pages and their lines above it; a link to the page that it does not return is dashed, its own links solid; while it is focused, the names of its linked pages come before the faded topic names (a topic name under one is hidden).
- **Every Dot Is Content** — in the map, each dot is a real note, file or link, and each grey area is a topic with its name and page count on it, on one line (the main subjects are in the List, the quick switcher and the page window's Topic tab; a second line under the name lay on the dots). No decorative dots, specks, particles or background patterns.
- **One Purple** — purple (`--accent`) is the only hue. It means "do this" and "you are here on the map": the primary button, keyboard focus (`--ring`), links on hover, a drop target, and the focused dot with its links in the map. A choice that is on (pressed toggle, chosen segment, current nav item, selected row or tab) is neutral: the `--pressed` fill or a strong edge with bold text (design round 2, 2026-11-15), so purple on a screen always points at the next action. Never on status, data series, backgrounds or decoration; components use the role tokens, never `--purple-*`.

- **One Look Per Choice** (review 2026-11-14) — either/or is the segmented control `.seg` (mode, theme, Topics/Sources, Graph/List); on/off is a pressed `.btn` with the `.toggle-mark` check box; tabs have an underline; the menu a soft fill. Never a second look for one of these.
- **One Primary Per View** — one `.btn--primary` on screen, on the forward path: Send on the home view (the result's Done, Update, Undo and Check for the answer are plain buttons, since Send stays on screen), Save in a form, Open in the page window; buttons in list rows are never primary. Checked by `ui-src/scripts/check-design-rules.mjs` in the states its header lists (home idle, with waiting items, after an Add, with an Add that waits; History; the graph; the page window and its Edit form), not in the others.
- **Errors Read As Errors** — every failure uses the `.notice--error` box (warning icon, soft fill, strong edge) and names the next step; a wait uses the busy notice with the time waited, never steps the interface cannot know.
- **Results First** — on a result screen the result and its actions come before the explanation of how it was made (Ask: answer, actions, sources, path; Add: heading, actions, where it was filed). The Ask answer fills the width of its card like the blocks under it, with no reading measure (operator, 2026-11-15).
- **Touch 44** — on a coarse pointer every control is at least 44 px high; checked by the same script.
- **Busy Keeps Its Width** (operator, 2026-11-24) — a button that works shows a small turning ring and its busy text inside itself (`components/BusyLabel.tsx`), carries `aria-busy` and is unavailable (`unavailable(busy)`); the label and "ring + busy text" share one grid cell, so the button is always as wide as the wider of the two and nothing moves. The side bar's Copilot retry is an icon button whose icon turns instead.
- **Present Is Status, New Is Alert** (operator, 2026-11-24) — an error box already there when a view opens is `role="status"` (it is the view's state); one that appears later, after an action or a late answer, is `role="alert"` (`components/Notice.tsx`, `ViewOpening` around the view in `App.tsx`).
- **A Filtered List Says Why It Is Empty** (operator, 2026-11-24) — when nothing matches, the List's one row names what narrows it (the search, the focus on a page, the filters) and has "Clear filters".

## Icon
A faceted volcanic-glass stone in the accent purples with a white geometric N on top (a nod to OneNote's N); original geometry, not any product's logo. Source `assets/icon.svg`; `assets/obsidinote.ico` (16 to 256 px) for the app and shortcuts; `assets/favicon.svg` + `assets/favicon.ico` (16/32/48) for the web UI. Regenerate all of them with `python -I tools/make-icon.py assets` (needs Pillow); never edit the PNG or ICO by hand.

## Icons
One set, one component (operator, 2026-11-24): `ui-src/src/components/icons.tsx`, used as `<Icon name="..." />`; a new icon is added there, never drawn inline in a component. Outline icons on a 16 px grid, 1.5 px round stroke, no fill, `currentColor` (so they take `--ink` or `--muted` from their parent), decorative (`aria-hidden`; the button or text beside carries the name), sized by the `.icon` class (16 px; a smaller place sets its size on `.icon` in its own sheet, never width/height per use). The on/off check box (`toggle-off`/`toggle-on`) is drawn on its own 12 px grid. The names: plus, graph, history, journal, meeting, search, add, info, pencil, lock, warn, refresh, chevron, paperclip, settings, check, filter, close, back, forward, fit, sort-up, sort-down, toggle-off, toggle-on. Not icons, so not in the set: the map itself and the legend's small samples of it (`graph/StageChrome.tsx`), which are drawn with the map's own classes so they look exactly like the map.

## Accepted deviations
Shared rules this project breaks on purpose, each with its reason (operator decisions; the dated ones 2026-11-24).
- **Graph title width** — the knowledge graph's title starts at the left of the full-width view, not on the 880 px column of Add or ask and History; the map uses the window's width.
- **The box is labelled by its heading** — the Add or ask box has no visible label of its own: the view's `h1` above it names it (`aria-labelledby`), and the placeholder says what may go in. A second label line would repeat the heading and push the box down (it must stay on the first screen at 720 and 390 px, One Primary Per View's check).
- **Spacing tokens stay px** — `--space-*` are px, not rem: the root font size is 13 px (`html { font-size: var(--text-body) }`), so rem steps would shrink every space by a fifth (16 px would become 13 px) and break the 4 px grid; the text sizes carry the reader's zoom.
- **Theme is a segmented control** — System / Light / Dark is the `.seg` in the side bar's footer, not a square icon button in a header: either/or is a segmented control here (One Look Per Choice), the app has no header bar, and a two-state toggle would lose "System".
- **Dialogs keep their look** — no Close button in the header of the small dialogs (new vault, set up, Settings, Archive/Delete/Merge confirms): Cancel in the footer and Esc close them, and the page window, the one large dialog, has its own Close. Widths stay as they are (the form dialogs about 560 px; the page window wider for its columns), vertically centred.
- **No Backspace removes a tag** — Backspace in an empty tag field does not remove the last tag: removing a tag writes to OneNote at once (no undo in the field), so a key pressed to correct a typo must never take a tag off; each tag's own remove button does it.
- **Map options stay in the map's header** — "Group the map by" (Topics / Sources / Tags) and the Tags bar sit in the graph's header, not in Filter: they choose what the areas are, are switched often, and Filter is for hiding pages.
- **Loading is a status line** — cards and lists (the recent pages, History, the map and List) show one status line while they load, no skeletons: the reads are short and local, and a placeholder shape would promise a layout the content may not have (the map's no-placeholder decision, 2026-11-13).

## Motion
120–200 ms ease-out on opacity/transform only; global `prefers-reduced-motion` rule.

## Do's / Don'ts
- Do: 2px `:focus-visible` outline with 2px offset; `tabular-nums` on numbers.
- Don't: gradient text, glassmorphism, glowing shadows, "connected" status pills.
