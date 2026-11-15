// The parts of the Add box under its text field: the "From:" choice, the intent line and the
// keyboard help. Render only; the box's state lives in Composer.tsx.
import type { Mode } from '../api'
import type { IntentLine as IntentLineData } from '../model/intentWording'
import { ORIGINS, TYPED_LABEL } from '../model/origins'
import { AddIcon, AskIcon, InfoIcon } from './icons'

/** Where the text came from (model/origins.ts); '' = typed. */
export function FromChoice({ origin, onChange }: { origin: string; onChange: (origin: string) => void }) {
  return (
    <div className="composer__from">
      <label htmlFor="composer-from">From</label>
      <select id="composer-from" className="field composer__from-select" value={origin} onChange={(e) => onChange(e.target.value)}>
        <option value="">{TYPED_LABEL}</option>
        {ORIGINS.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  )
}

/** What the text will do, with its "Add instead / Ask instead" switch. */
export function IntentLine({ intent, line, error, onFlip }: { intent: string | undefined; line: IntentLineData; error: string; onFlip: (mode: Mode) => void }) {
  const LineIcon = intent === 'ask' ? AskIcon : intent === 'add' ? AddIcon : InfoIcon
  return (
    <p className="composer__intent" role="status">
      <LineIcon />
      <span>
        {error ? (
          <>Cannot tell yet: {error}</>
        ) : (
          <>
            {line.lead && <b>{line.lead}: </b>}
            {line.text}
          </>
        )}
        {line.flip && !error && (
          <>
            {' '}
            <button type="button" className="link-btn" onClick={() => onFlip(line.flip!.mode)}>
              {line.flip.label}
            </button>
          </>
        )}
      </span>
    </p>
  )
}

export function KeysHelp() {
  return (
    <div className="composer__help">
      <button type="button" className="btn btn--icon btn--ghost composer__help-btn" aria-label="Keyboard shortcuts" aria-describedby="composer-keys">
        <InfoIcon />
      </button>
      <div id="composer-keys" role="tooltip" className="composer__keys">
        <span><kbd>Ctrl</kbd> <kbd>1</kbd></span><span>Add</span>
        <span><kbd>Ctrl</kbd> <kbd>2</kbd></span><span>Ask</span>
        <span><kbd>Enter</kbd></span><span>Send</span>
        <span><kbd>Shift</kbd> <kbd>Enter</kbd></span><span>New line</span>
        <span><kbd>Ctrl</kbd> <kbd>K</kbd></span><span>Find a page or topic</span>
      </div>
    </div>
  )
}
