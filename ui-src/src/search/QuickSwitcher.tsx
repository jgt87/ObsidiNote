// The quick switcher: Ctrl+K anywhere opens one search box over the ACTIVE vault's pages and
// topics. Enter on a page opens the knowledge graph with that page's dialog; on a topic, the graph
// with the search set to topic:<path>.
//
// Data: the active vault's graph model, fetched the first time the switcher opens and kept in
// memory for the session (refetched when the vault changes; refreshed quietly on each later open,
// the kept copy answers meanwhile). Nothing is stored in the browser.

import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react'
import { buildIndex, type GraphIndex } from '../graph/graphIndex'
import type { GraphModel } from '../graph/model'
import { plural } from '../graph/format'
import { isFindKey } from '../model/keys'
import { moveActive, requestFor, switcherList, type FindRequest } from './switcherModel'
import './QuickSwitcher.css'

type Data = { status: 'idle' } | { status: 'loading' } | { status: 'ready'; index: GraphIndex } | { status: 'error'; message: string }

export interface QuickSwitcherProps {
  /** Key of the active vault (e.g. its graph ref as JSON); null when no vault is active. */
  vaultKey: string | null
  /** Loads the active vault's model. */
  load: (signal: AbortSignal) => Promise<GraphModel>
  onPick: (request: FindRequest) => void
}

/** Mounted once by the app: owns the Ctrl+K listener, the kept model and the dialog. */
export function QuickSwitcher({ vaultKey, load, onPick }: QuickSwitcherProps) {
  const [open, setOpen] = useState(false)
  const [data, setData] = useState<Data>({ status: 'idle' })
  const loadedFor = useRef<string | null>(null)
  const loadRef = useRef(load)
  loadRef.current = load
  const ctl = useRef<AbortController | null>(null)

  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (!isFindKey(e)) return
      e.preventDefault()
      setOpen(true)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const fetchModel = useCallback((quiet: boolean) => {
    if (!vaultKey) return
    ctl.current?.abort()
    const c = new AbortController()
    ctl.current = c
    if (!quiet) setData({ status: 'loading' })
    loadRef.current(c.signal).then(
      (model) => {
        if (c.signal.aborted) return
        loadedFor.current = vaultKey
        setData({ status: 'ready', index: buildIndex(model) })
      },
      (e: unknown) => {
        if (c.signal.aborted || quiet) return
        setData({ status: 'error', message: e instanceof Error && e.message ? e.message : 'The vault could not be read.' })
      },
    )
  }, [vaultKey])

  // Another vault: drop the kept model.
  useEffect(() => {
    if (loadedFor.current !== null && loadedFor.current !== vaultKey) {
      ctl.current?.abort()
      loadedFor.current = null
      setData({ status: 'idle' })
    }
  }, [vaultKey])

  useEffect(() => {
    if (!open) return
    // Runs when it opens (or the vault changes while open); a kept model is refreshed quietly.
    fetchModel(loadedFor.current === vaultKey)
  }, [open, fetchModel, vaultKey])

  useEffect(() => () => ctl.current?.abort(), [])

  if (!open) return null
  return (
    <SwitcherDialog
      data={vaultKey ? data : { status: 'error', message: 'No vault is active. Choose or make a vault first.' }}
      onRetry={vaultKey ? () => fetchModel(false) : undefined}
      onClose={() => setOpen(false)}
      onPick={(r) => {
        setOpen(false)
        onPick(r)
      }}
    />
  )
}

interface DialogProps {
  data: Data
  onRetry?: () => void
  onClose: () => void
  onPick: (request: FindRequest) => void
}

function SwitcherDialog({ data, onRetry, onClose, onPick }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const returnTo = useRef<HTMLElement | null>(document.activeElement instanceof HTMLElement ? document.activeElement : null)
  const picked = useRef(false)
  const closeRef = useRef(onClose)
  closeRef.current = onClose
  const [text, setText] = useState('')
  const [activeRow, setActiveRow] = useState(0)

  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
    inputRef.current?.focus()
    const back = returnTo.current
    // Focus returns where it was, unless a pick moved on to the graph.
    return () => {
      if (!picked.current) requestAnimationFrame(() => back?.isConnected && back.focus())
    }
  }, [])

  const index = data.status === 'ready' ? data.index : null
  const list = useMemo(() => (index ? switcherList(index, text) : null), [index, text])
  const rows = list?.rows ?? []
  const current = rows.length ? Math.min(activeRow, rows.length - 1) : -1

  const pick = (i: number) => {
    const row = rows[i]
    if (!row || !index) return
    const r = requestFor(index, row.item)
    if (!r) return
    picked.current = true
    onPick(r)
  }

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.nativeEvent.isComposing) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const next = moveActive(current, e.key === 'ArrowDown' ? 1 : -1, rows.length)
      setActiveRow(next)
      document.getElementById(`qs-row-${rows[next]?.key}`)?.scrollIntoView({ block: 'nearest' })
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (current >= 0) pick(current)
    }
  }

  const activeId = current >= 0 ? `qs-row-${rows[current].key}` : undefined
  const announce = !list ? '' : list.suggested ? '' : rows.length ? `${plural(rows.length + list.hidden, 'result')}` : 'No pages or topics match'

  return (
    <dialog
      ref={ref}
      className="qs"
      aria-label="Find a page or topic"
      onCancel={(e) => {
        // Esc clears the box first, then closes.
        e.preventDefault()
        if (text) {
          setText('')
          setActiveRow(0)
        } else closeRef.current()
      }}
      onClick={(e) => {
        if (e.target === ref.current) closeRef.current()
      }}
    >
      <div className="qs__bar">
        <svg className="qs__icon" viewBox="0 0 16 16" aria-hidden="true">
          <circle cx="7" cy="7" r="4.5" />
          <path d="M10.5 10.5L14 14" />
        </svg>
        <input
          ref={inputRef}
          className="qs__input"
          type="text"
          role="combobox"
          aria-expanded={rows.length > 0}
          aria-controls="qs-list"
          aria-activedescendant={activeId}
          aria-autocomplete="list"
          aria-label="Find a page or topic"
          placeholder="Find a page or topic"
          autoComplete="off"
          spellCheck={false}
          value={text}
          onChange={(e) => {
            setText(e.target.value)
            setActiveRow(0)
          }}
          onKeyDown={onKeyDown}
        />
        {data.status === 'loading' && <span className="qs__spinner motion-alt" role="status" aria-label="Reading the vault" />}
        <kbd className="qs__kbd">Esc</kbd>
      </div>

      <div className="qs__body">
        {data.status === 'loading' && <p className="qs__state">Reading the vault…</p>}
        {data.status === 'error' && (
          <div className="qs__state" role="alert">
            <p>{data.message}</p>
            {onRetry && (
              <button type="button" className="btn btn--sm" onClick={onRetry}>
                Try again
              </button>
            )}
          </div>
        )}
        {list && (
          <>
            {list.suggested && rows.length > 0 && <p className="qs__heading" id="qs-heading">Start here</p>}
            {rows.length > 0 ? (
              <ul id="qs-list" className="qs__list" role="listbox" aria-label={list.suggested ? 'Start here' : 'Results'}>
                {rows.map((r, i) => (
                  <li
                    key={r.key}
                    id={`qs-row-${r.key}`}
                    role="option"
                    aria-selected={i === current}
                    className="qs__row"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => pick(i)}
                    onPointerMove={() => i !== current && setActiveRow(i)}
                  >
                    <span className="qs__label">{r.label}</span>
                    {r.context && <span className="qs__context">{r.context}</span>}
                    {r.tag && <span className="qs__tag">{r.tag}</span>}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="qs__state">{list.suggested ? 'This vault has no pages yet.' : `No pages or topics match “${text.trim()}”.`}</p>
            )}
            {list.hidden > 0 && <p className="qs__more">{plural(list.hidden, 'more match', 'more matches')} not shown. Add words or a filter (type:, topic:, site:, after:, is:).</p>}
          </>
        )}
      </div>
      <p className="qs__hint">
        <kbd>↑</kbd> <kbd>↓</kbd> to move · <kbd>Enter</kbd> to open · filters: type: topic: site: after: before: is:
      </p>
      <span className="qs__sr" aria-live="polite">
        {announce}
      </span>
    </dialog>
  )
}
