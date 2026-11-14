import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import type { NotebooksState, NotebookState } from '../hooks/useServerData'
import { attentionNotes } from '../model/attention'
import { Rail } from './Rail'

const notebooks = { list: [], activeId: null, shownId: null, loading: false, error: '', message: '', mode: 'none', choose: () => {}, adopt: () => {} } as unknown as NotebooksState
const notebook = { data: null, loading: false, error: '', reload: () => {} } as unknown as NotebookState
const status = (state: 'no-tab' | 'skipped') => ({
  app: 'ObsidiNote',
  version: 'v0.0.0',
  uiPort: 8767,
  oneNote: { state: 'window' as const, running: true, notebookOpen: true, notebook: 'ObsidiNote' },
  copilot: { state, port: 9334 },
})
const render = (state: 'no-tab' | 'skipped') =>
  renderToStaticMarkup(
    <Rail view="home" notebooks={notebooks} notebook={notebook} notes={attentionNotes(status(state), false)} onNewVault={() => {}} onSetUp={() => {}} onRetryCopilot={async () => ''} />,
  )

describe('the Copilot note in the side bar', () => {
  it('has a labelled refresh button when Copilot is not connected', () => {
    const html = render('no-tab')
    expect(html).toContain('aria-label="Connect Copilot again"')
    expect(html).toContain('type="button"')
  })
  it('has no refresh button when Copilot was turned off for this start', () => {
    expect(render('skipped')).not.toContain('Connect Copilot again')
  })
})
