import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { SettingsDialog } from './SettingsDialog'

const noop = () => {}

describe('SettingsDialog: the version in the top right', () => {
  it('shows the running version beside the title, with one "v"', () => {
    for (const version of ['0.10.2', 'v0.10.2']) {
      const html = renderToStaticMarkup(<SettingsDialog onClose={noop} version={version} />)
      expect(html).toMatch(/<div class="st__title-row"><h2 id="st-title"[^>]*>Settings<\/h2><span class="st__version" title="ObsidiNote version 0.10.2">v0.10.2<\/span><\/div>/)
    }
  })

  it('shows no version while it is not known', () => {
    expect(renderToStaticMarkup(<SettingsDialog onClose={noop} />)).not.toContain('st__version')
  })
})
