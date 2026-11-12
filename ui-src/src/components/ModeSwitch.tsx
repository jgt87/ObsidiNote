import type { Mode } from '../api'

const MODES: { mode: Mode; label: string }[] = [
  { mode: 'auto', label: 'Auto' },
  { mode: 'add', label: 'Add' },
  { mode: 'ask', label: 'Ask' },
]

/** Auto / Add / Ask as a segmented control of toggle buttons. */
export function ModeSwitch({ mode, onChange }: { mode: Mode; onChange: (m: Mode) => void }) {
  return (
    <div className="seg" role="group" aria-label="Mode">
      {MODES.map((m) => (
        <button key={m.mode} type="button" className="seg__btn" aria-pressed={mode === m.mode} onClick={() => onChange(m.mode)}>
          {m.label}
        </button>
      ))}
    </div>
  )
}
