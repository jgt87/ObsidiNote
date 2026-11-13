import './AskOptions.css'

export interface AskChoices {
  sources: string[]
  includeArchived: boolean
}

/** What Ask reads besides the active vault: other vaults and connected notebooks (read only), and
 *  archived pages. Session state in memory; nothing is stored. */
export function AskOptions({ choices, options, onChange }: { choices: AskChoices; options: { id: string; label: string }[]; onChange: (c: AskChoices) => void }) {
  const toggle = (id: string) => onChange({ ...choices, sources: choices.sources.includes(id) ? choices.sources.filter((s) => s !== id) : [...choices.sources, id] })
  const extra = choices.sources.length + (choices.includeArchived ? 1 : 0)
  return (
    <details className="ask-opts">
      <summary className="ask-opts__summary">Ask reads: the active vault{extra ? ` + ${extra} more` : ''}</summary>
      <div className="ask-opts__body">
        <label className="ask-opts__row">
          <input type="checkbox" checked={choices.includeArchived} onChange={(e) => onChange({ ...choices, includeArchived: e.target.checked })} />
          Include archived pages
        </label>
        {options.length > 0 && (
          <fieldset className="ask-opts__set">
            <legend className="ask-opts__legend">Also read (never written)</legend>
            {options.map((o) => (
              <label key={o.id} className="ask-opts__row">
                <input type="checkbox" checked={choices.sources.includes(o.id)} onChange={() => toggle(o.id)} />
                {o.label}
              </label>
            ))}
          </fieldset>
        )}
      </div>
    </details>
  )
}
