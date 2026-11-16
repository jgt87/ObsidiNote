// The quick switcher: Ctrl+K anywhere opens one search box over the ACTIVE vault's pages and
// topics. Enter on a page opens the knowledge graph with that page's dialog; on a topic, the graph
// with the search set to topic:<path>.
//
// Data: the active vault's graph model, fetched the first time the switcher opens and kept in
// memory for the session (refetched when the vault changes; refreshed quietly on each later open,
// the kept copy answers meanwhile). Nothing is stored in the browser.

import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent, type RefObject } from 'react'
import { buildIndex, type GraphIndex } from '../graph/graphIndex'
import type { GraphModel } from '../graph/model'
import { plural } from '../graph/format'
import { isFindKey } from '../model/keys'
import { emptyListText, moveActive, requestFor, rowDomId, switcherAnnouncement, switcherList, type FindRequest, type SwitcherList, type SwitcherRow } from './switcherModel'
import './QuickSwitcher.css'

type Data = { status: 'idle' } | { status: 'loading' } | { status: 'ready'; index: GraphIndex } | { status: 'error'; message: string }

export interface QuickSwitcherProps {
  /** Key of the active vault (e.g. its graph ref as JSON); null when no vault is active. */
  vaultKey: string | null
  /** Loads the active vault's model. */
  load: (signal: AbortSignal) => Promise<GraphModel>
  onPick: (request: FindRequest) => void
}

const NO_VAULT: Data = { status: 'error', message: 'No vault is active. Choose or make a vault first.' }

/** Mounted once by the app: owns the Ctrl+K listener, the kept model and the dialog. */
export function QuickSwitcher({ vaultKey, load, onPick }: QuickSwitcherProps) {
  const [open, setOpen] = useState(false)
  useFindKey(() => setOpen(true))
  const { data, fetchModel } = useKeptModel(vaultKey, load, open)

  if (!open) return null
  return (
    <SwitcherDialog
      data={vaultKey ? data : NO_VAULT}
      onRetry={vaultKey ? () => fetchModel(false) : undefined}
      onClose={() => setOpen(false)}
      onPick={(r) => {
        setOpen(false)
        onPick(r)
      }}
    />
  )
}

/** Ctrl+K (isFindKey) anywhere in the window. */
function useFindKey(onFind: () => void) {
  const findRef = useRef(onFind)
  findRef.current = onFind
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (!isFindKey(e)) return
      e.preventDefault()
      findRef.current()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])
}

/** The active vault's model, kept in memory: loaded when the switcher opens (quietly when a copy
 *  for this vault is kept, which answers meanwhile), dropped when the vault changes. */
function useKeptModel(vaultKey: string | null, load: (signal: AbortSignal) => Promise<GraphModel>, open: boolean) {
  const [data, setData] = useState<Data>({ status: 'idle' })
  const loadedFor = useRef<string | null>(null)
  const loadRef = useRef(load)
  loadRef.current = load
  const ctl = useRef<AbortController | null>(null)

  const fetchModel = useCallback((quiet: boolean) => {
    if (!vaultKey) return
    ctl.current?.abort()
    const c = new AbortController()
    ctl.current = c
    if (!quiet) setData({ status: 'loading' })
    readModel(loadRef.current, c.signal, quiet, (next) => {
      if (next.status === 'ready') loadedFor.current = vaultKey
      setData(next)
    })
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
  return { data, fetchModel }
}

/** One read of the model: `done` gets the index, or the error unless the read was quiet (a kept
 *  copy keeps answering); nothing once `signal` is aborted (a newer read or another vault). */
function readModel(load: (signal: AbortSignal) => Promise<GraphModel>, signal: AbortSignal, quiet: boolean, done: (data: Data) => void) {
  load(signal).then(
    (model) => {
      if (!signal.aborted) done({ status: 'ready', index: buildIndex(model) })
    },
    (e: unknown) => {
      if (!signal.aborted && !quiet) done({ status: 'error', message: readError(e) })
    },
  )
}

const readError = (e: unknown): string => (e instanceof Error && e.message ? e.message : 'The vault could not be read.')

interface DialogProps {
  data: Data
  onRetry?: () => void
  onClose: () => void
  onPick: (request: FindRequest) => void
}

function SwitcherDialog({ data, onRetry, onClose, onPick }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const picked = useRef(false)
  const closeRef = useRef(onClose)
  closeRef.current = onClose
  useModal(ref, inputRef, picked)
  const [text, setText] = useState('')
  const [activeRow, setActiveRow] = useState(0)

  const { index, list, rows, current } = useSwitcherRows(data, text, activeRow)

  const pick = (i: number) => {
    const r = pickRequest(index, rows[i])
    if (!r) return
    picked.current = true
    onPick(r)
  }
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => onListKey(e, current, rows, setActiveRow, pick)
  const setTyped = (t: string) => {
    setText(t)
    setActiveRow(0)
  }

  return (
    <dialog
      ref={ref}
      className="qs"
      aria-label="Find a page or topic"
      onCancel={(e) => {
        // Esc clears the box first, then closes.
        e.preventDefault()
        if (text) setTyped('')
        else closeRef.current()
      }}
      onClick={(e) => {
        if (e.target === ref.current) closeRef.current()
      }}
    >
      <SwitcherBox inputRef={inputRef} text={text} onText={setTyped} onKeyDown={onKeyDown} activeRow={current >= 0 ? rows[current] : null} hasRows={rows.length > 0} loading={data.status === 'loading'} />

      <div className="qs__body">
        <DataState data={data} onRetry={onRetry} />
        {list && <Results list={list} text={text} current={current} onPick={pick} onPoint={(i) => i !== current && setActiveRow(i)} />}
      </div>
      <p className="qs__hint">
        <kbd>↑</kbd> <kbd>↓</kbd> to move · <kbd>Enter</kbd> to open · filters: type: topic: site: after: before: is:
      </p>
      <span className="qs__sr" aria-live="polite">
        {switcherAnnouncement(list)}
      </span>
    </dialog>
  )
}

/** The rows for the text typed (suggestions for an empty box) once the model is read, and the row
 *  the arrows are on: kept within the rows, -1 without any. */
function useSwitcherRows(data: Data, text: string, activeRow: number) {
  const index = data.status === 'ready' ? data.index : null
  const list = useMemo(() => (index ? switcherList(index, text) : null), [index, text])
  const rows = list?.rows ?? []
  const current = rows.length ? Math.min(activeRow, rows.length - 1) : -1
  return { index, list, rows, current }
}

interface BoxProps {
  inputRef: RefObject<HTMLInputElement | null>
  text: string
  onText: (text: string) => void
  onKeyDown: (e: KeyboardEvent<HTMLInputElement>) => void
  /** The row the arrows are on (aria-activedescendant); null without rows. */
  activeRow: SwitcherRow | null
  hasRows: boolean
  loading: boolean
}

/** The search box: a combobox over the list, a spinner while the vault is read, the Esc hint. */
function SwitcherBox({ inputRef, text, onText, onKeyDown, activeRow, hasRows, loading }: BoxProps) {
  return (
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
        aria-expanded={hasRows}
        aria-controls="qs-list"
        aria-activedescendant={activeRow ? rowDomId(activeRow.key) : undefined}
        aria-autocomplete="list"
        aria-label="Find a page or topic"
        placeholder="Find a page or topic"
        autoComplete="off"
        spellCheck={false}
        value={text}
        onChange={(e) => onText(e.target.value)}
        onKeyDown={onKeyDown}
      />
      {loading && <span className="qs__spinner motion-alt" role="status" aria-label="Reading the vault" />}
      <kbd className="qs__kbd">Esc</kbd>
    </div>
  )
}

/** Opens the dialog as a modal with the box focused; on close, focus returns where it was, unless
 *  a pick moved on to the graph. */
function useModal(ref: RefObject<HTMLDialogElement | null>, inputRef: RefObject<HTMLInputElement | null>, picked: RefObject<boolean>) {
  const returnTo = useRef<HTMLElement | null>(document.activeElement instanceof HTMLElement ? document.activeElement : null)
  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
    inputRef.current?.focus()
    const back = returnTo.current
    return () => {
      if (!picked.current) requestAnimationFrame(() => back?.isConnected && back.focus())
    }
  }, [ref, inputRef, picked])
}

/** What a row asks the graph to do; null when the row or its item is gone. */
function pickRequest(index: GraphIndex | null, row: SwitcherRow | undefined): FindRequest | null {
  if (!row || !index) return null
  return requestFor(index, row.item)
}

/** The box's keys: arrows move through the rows (wrapping, the row scrolled into view), Enter opens
 *  the active one. Ignored while an input method is composing. */
function onListKey(e: KeyboardEvent<HTMLInputElement>, current: number, rows: SwitcherRow[], setActive: (i: number) => void, pick: (i: number) => void) {
  if (e.nativeEvent.isComposing) return
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault()
    const next = moveActive(current, e.key === 'ArrowDown' ? 1 : -1, rows.length)
    setActive(next)
    const row = rows[next]
    if (row) document.getElementById(rowDomId(row.key))?.scrollIntoView({ block: 'nearest' })
  } else if (e.key === 'Enter') {
    e.preventDefault()
    if (current >= 0) pick(current)
  }
}

/** Loading, or the error with "Try again" when it can be retried. */
function DataState({ data, onRetry }: { data: Data; onRetry?: () => void }) {
  if (data.status === 'loading') return <p className="qs__state">Reading the vault…</p>
  if (data.status !== 'error') return null
  return (
    <div className="qs__state" role="alert">
      <p>{data.message}</p>
      {onRetry && (
        <button type="button" className="btn btn--sm" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  )
}

interface ResultsProps {
  list: SwitcherList
  text: string
  current: number
  onPick: (i: number) => void
  onPoint: (i: number) => void
}

/** The rows ("Start here" for an empty box), the line when there are none, and how many more match. */
function Results({ list, text, current, onPick, onPoint }: ResultsProps) {
  const { rows } = list
  return (
    <>
      {list.suggested && rows.length > 0 && <p className="qs__heading" id="qs-heading">Start here</p>}
      {rows.length > 0 ? (
        <ul id="qs-list" className="qs__list" role="listbox" aria-label={list.suggested ? 'Start here' : 'Results'}>
          {rows.map((r, i) => (
            <li key={r.key} id={rowDomId(r.key)} role="option" aria-selected={i === current} className="qs__row" onMouseDown={(e) => e.preventDefault()} onClick={() => onPick(i)} onPointerMove={() => onPoint(i)}>
              <span className="qs__label">{r.label}</span>
              {r.context && <span className="qs__context">{r.context}</span>}
              {r.tag && <span className="qs__tag">{r.tag}</span>}
            </li>
          ))}
        </ul>
      ) : (
        <p className="qs__state">{emptyListText(list, text)}</p>
      )}
      {list.hidden > 0 && <p className="qs__more">{plural(list.hidden, 'more match', 'more matches')} not shown. Add words or a filter (type:, topic:, site:, after:, is:).</p>}
    </>
  )
}
