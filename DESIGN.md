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
- **Weight Is Relevance** — in the map, link strength is line weight and opacity, and dot size is the link weight of the page (strengths of the links to it plus half of its own, one smooth scale; hubs get a thicker outline, not a size jump); clusters are grey areas, labelled by topic. Links between two topics are one soft line from area to area whose width is the summed strength of their links, bent around any third topic in its way through the middle of the gaps (and drawn under the solid areas), so it never lies across or under a third topic; topics with links between them are placed next to each other (strongest first), so a line rarely needs to bend; at rest only the 8 heaviest, all of them from 1.5x the fitted zoom, all of a topic's when one of its pages is focused; ends on the facing side, spread along the rim (the page-to-page lines appear for the focused page only). A topic name sits bold in the middle of its own area, in room the layout keeps free of dots (`labelSize.ts` labelSlot; review 2026-11-14: names lay on 1 to 5 of their own dots), sized for the zoom the map is fitted to (a map of a few hundred pages is fitted zoomed out, where a name covers more of it; `layout.ts` layoutGraph lays out again with that much more room), and fades out while the pointer is over that area or one of its pages is focused.
- **Every Dot Is Content** — in the map, each dot is a real note, file or link, and each grey area is a topic with its name on it (the page count and main subjects are in the List, the quick switcher and the page window's Topic tab; on the map that line lay on the dots). No decorative dots, specks, particles or background patterns.
- **One Purple** — purple (`--accent`) is the only hue. It means "do this" and "you are here on the map": the primary button, keyboard focus (`--ring`), links on hover, a drop target, and the focused dot with its links in the map. A choice that is on (pressed toggle, chosen segment, current nav item, selected row or tab) is neutral: the `--pressed` fill or a strong edge with bold text (design round 2, 2026-11-15), so purple on a screen always points at the next action. Never on status, data series, backgrounds or decoration; components use the role tokens, never `--purple-*`.

- **One Look Per Choice** (review 2026-11-14) — either/or is the segmented control `.seg` (mode, theme, Topics/Sources, Graph/List); on/off is a pressed `.btn` with the `.toggle-mark` check box; tabs have an underline; the menu a soft fill. Never a second look for one of these.
- **One Primary Per View** — one `.btn--primary` on screen, on the forward path: Send on the home view (the result's Done, Update, Undo and Check for the answer are plain buttons, since Send stays on screen), Save in a form, Open in the page window; buttons in list rows are never primary. Checked by `ui-src/scripts/check-design-rules.mjs` in the states its header lists (home idle, with waiting items, after an Add, with an Add that waits; History; the graph; the page window and its Edit form), not in the others.
- **Errors Read As Errors** — every failure uses the `.notice--error` box (warning icon, soft fill, strong edge) and names the next step; a wait uses the busy notice with the time waited, never steps the interface cannot know.
- **Results First** — on a result screen the result and its actions come before the explanation of how it was made (Ask: answer, actions, sources, path; Add: heading, actions, where it was filed). The Ask answer fills the width of its card like the blocks under it, with no reading measure (operator, 2026-11-15).
- **Touch 44** — on a coarse pointer every control is at least 44 px high; checked by the same script.
- Accepted deviation: the knowledge graph's title starts at the left of the full-width view, not on the 880 px column of Add or ask and History; the map uses the window's width.

## Icon
A faceted volcanic-glass stone in the accent purples with a white geometric N on top (a nod to OneNote's N); original geometry, not any product's logo. Source `assets/icon.svg`; `assets/obsidinote.ico` (16 to 256 px) for the app and shortcuts; `assets/favicon.svg` + `assets/favicon.ico` (16/32/48) for the web UI. Regenerate all of them with `python -I tools/make-icon.py assets` (needs Pillow); never edit the PNG or ICO by hand.

## Motion
120–200 ms ease-out on opacity/transform only; global `prefers-reduced-motion` rule.

## Do's / Don'ts
- Do: 2px `:focus-visible` outline with 2px offset; `tabular-nums` on numbers.
- Don't: gradient text, glassmorphism, glowing shadows, "connected" status pills.
