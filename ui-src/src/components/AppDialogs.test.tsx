import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { AppDialogs, type AppDialog } from './AppDialogs'

const noop = () => {}
const shown = { id: '{11111111-1111-1111-1111-111111111111}{1}{B0}', name: 'Reading notes', vault: false, active: false, location: 'this PC' }
const render = (dialog: AppDialog, withShown = true) =>
  renderToStaticMarkup(<AppDialogs dialog={dialog} onClose={noop} notebooks={[shown]} shown={withShown ? shown : undefined} version="v1.2.3" onSettingsSaved={noop} onTagsChanged={noop} onAdopt={noop} />)

describe('AppDialogs: one dialog at a time', () => {
  it('shows nothing when no dialog is open, and no Set up without a shown notebook', () => {
    expect(render(null)).toBe('')
    expect(render('set-up', false)).toBe('')
  })
  it('shows the asked dialog only', () => {
    const settings = render('settings')
    expect(settings).toContain('v1.2.3')
    expect(render('set-up')).toContain('Reading notes')
    for (const d of ['settings', 'new-vault', 'set-up'] as const) expect(render(d).match(/<dialog/g)?.length).toBe(1)
  })
})
