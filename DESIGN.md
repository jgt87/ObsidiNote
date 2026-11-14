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
- **Weight Is Relevance** — in the map, link strength is line weight and opacity; clusters are grey areas, labelled by topic. Links between two topics are one soft line from area to area whose width is the number of links (the page-to-page lines appear for the focused page only); topic names never lie on another topic.
- **Every Dot Is Content** — in the map, each dot is a real note, file or link, and each grey area is a topic with a visible label (name, page count, main subjects). No decorative dots, specks, particles or background patterns.
- **One Purple** — purple (`--accent`) is the only hue. It marks the primary button, the active nav item and selected controls, keyboard focus (`--ring`), links on hover, and the focused dot with its links in the map. Never on status, data series, backgrounds or decoration; components use the role tokens, never `--purple-*`.

## Icon
A faceted volcanic-glass stone in the accent purples with a white geometric N on top (a nod to OneNote's N); original geometry, not any product's logo. Source `assets/icon.svg`; `assets/obsidinote.ico` (16 to 256 px) for the app and shortcuts; `assets/favicon.svg` + `assets/favicon.ico` (16/32/48) for the web UI. Regenerate all of them with `python -I tools/make-icon.py assets` (needs Pillow); never edit the PNG or ICO by hand.

## Motion
120–200 ms ease-out on opacity/transform only; global `prefers-reduced-motion` rule.

## Do's / Don'ts
- Do: 2px `:focus-visible` outline with 2px offset; `tabular-nums` on numbers.
- Don't: gradient text, glassmorphism, glowing shadows, "connected" status pills.
