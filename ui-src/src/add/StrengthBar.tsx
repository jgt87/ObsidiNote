import { clampStrength, strengthLabel } from './format'

/** Three segments; the filled ones are the link's strength (Weight Is Relevance). */
export function StrengthBar({ strength }: { strength: number }) {
  const s = clampStrength(strength)
  return (
    <span className="add-bar" role="img" aria-label={strengthLabel(s)}>
      {[1, 2, 3].map((i) => (
        <i key={i} className={i <= s ? 'add-bar__seg add-bar__seg--on' : 'add-bar__seg'} />
      ))}
    </span>
  )
}
