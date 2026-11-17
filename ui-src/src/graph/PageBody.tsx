// The page's own text in the page window, read only (design round 2, 2026-11-15: the window showed
// the summary and links and sent the reader to OneNote for the text). Read from OneNote when the
// window shows the page, kept in memory only, never edited here: "Open in OneNote" stays the way
// to change text. Parsing is bodyText.ts; this file only loads and draws.

import { Fragment, useEffect, useState, type ReactNode } from 'react'
import { Notice } from '../components/Notice'
import { WebLink } from '../components/WebLink'
import { bodyBlocks, type Block, type ListItem, type Part } from './bodyText'

export interface PageBodyResult {
  markdown: string
  truncated: boolean
}

interface Props {
  pageId: string
  load: (pageId: string, signal: AbortSignal) => Promise<PageBodyResult>
  /** Whether a linked page is on this map (then its link opens it here). */
  hasPage: (id: string) => boolean
  onOpenPage: (id: string) => void
}

type State = { status: 'loading' } | { status: 'error'; message: string } | { status: 'ready'; blocks: Block[]; truncated: boolean }

export function PageBody({ pageId, load, hasPage, onOpenPage }: Props) {
  const [state, setState] = useState<State>({ status: 'loading' })
  const [again, setAgain] = useState(0)
  useEffect(() => {
    // An answer for a page that is no longer shown is dropped (abort, and the flag for a loader
    // that ignores the signal).
    const ctl = new AbortController()
    let live = true
    setState({ status: 'loading' })
    load(pageId, ctl.signal).then(
      (r) => live && setState({ status: 'ready', blocks: bodyBlocks(r.markdown), truncated: r.truncated }),
      (e: unknown) => live && setState({ status: 'error', message: e instanceof Error ? e.message : 'ObsidiNote did not answer.' }),
    )
    return () => {
      live = false
      ctl.abort()
    }
  }, [pageId, load, again])

  if (state.status === 'loading') return <Notice busy title="Reading the page from OneNote" />
  if (state.status === 'error') {
    return (
      <Notice
        error
        title="The page text could not be read."
        actions={
          <button type="button" className="btn btn--sm" onClick={() => setAgain((n) => n + 1)}>
            Try reading the page again
          </button>
        }
      >
        <p>{state.message}</p>
      </Notice>
    )
  }
  if (!state.blocks.length) return <p className="kg-note">This page has no text yet. Add it in OneNote.</p>

  const part = (p: Part, i: number): ReactNode => {
    let node: ReactNode = p.text
    if (p.code) node = <code>{node}</code>
    if (p.bold) node = <strong>{node}</strong>
    if (p.italic) node = <em>{node}</em>
    if (p.strike) node = <s>{node}</s>
    if (p.pageId && hasPage(p.pageId)) {
      const id = p.pageId
      return (
        <button key={i} type="button" className="kg-linkbtn kg-body__page" onClick={() => onOpenPage(id)}>
          {node}
        </button>
      )
    }
    if (p.href) {
      // onenote: opens OneNote itself, mailto: the mail app; a web address opens in the default
      // browser (WebLink, 2026-11-17).
      if (/^https?:/i.test(p.href))
        return (
          <WebLink key={i} href={p.href}>
            {node}
          </WebLink>
        )
      return (
        <a key={i} href={p.href}>
          {node}
        </a>
      )
    }
    return <Fragment key={i}>{node}</Fragment>
  }
  const line = (parts: Part[]) => parts.map(part)
  const item = (it: ListItem, i: number) => (
    <li key={i} data-depth={it.depth ? Math.min(it.depth, 4) : undefined} data-task={it.done === undefined ? undefined : it.done ? 'done' : 'open'}>
      {it.done !== undefined && <span className="kg-sr">{it.done ? 'Done: ' : 'To do: '}</span>}
      {line(it.parts)}
    </li>
  )
  return (
    <div className="kg-body">
      {state.blocks.map((b, i) => {
        if (b.kind === 'heading') {
          // Under the window's own h2 (the title) and the "Page content" label.
          const H = b.level === 1 ? 'h3' : b.level === 2 ? 'h4' : 'h5'
          return <H key={i}>{line(b.parts)}</H>
        }
        if (b.kind === 'list') {
          const L = b.ordered ? 'ol' : 'ul'
          return <L key={i}>{b.items.map(item)}</L>
        }
        if (b.kind === 'table') {
          return (
            <div key={i} className="kg-body__table">
              <table>
                <thead>
                  <tr>
                    {b.head.map((c, k) => (
                      <th key={k} scope="col">
                        {line(c)}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {b.rows.map((r, k) => (
                    <tr key={k}>
                      {r.map((c, m) => (
                        <td key={m}>{line(c)}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        }
        return <p key={i}>{line(b.parts)}</p>
      })}
      {state.truncated && <p className="kg-note">This is the first part of a long page. Open it in OneNote for the rest.</p>}
    </div>
  )
}
