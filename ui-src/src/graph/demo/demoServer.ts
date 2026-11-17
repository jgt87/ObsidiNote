// The graph demo's stand-ins for the server: never the real routes (the dev server proxies /api to
// a running app). They change the demo's own model in memory. Each ?<name>=fail shows that call's
// error; ?link=slow keeps "Link it" busy for a minute; ?body=fail|empty|long shows the page text's
// other states. Pure but for its timers (tests: demoServer.test.ts); main.tsx renders the page.

import type { PageEditRequest } from '../editModel'
import type { GraphModel, GraphPage } from '../model'
import type { PageBodyResult } from '../PageBody'

export const WRITER_ELSEWHERE = 'Read only: another ObsidiNote is writing in this vault.'

/** An invented page text: headings, lists, a task list, a table, a web link and a link to another
 *  page of the map (`other`). */
export function demoPageText(other: Pick<GraphPage, 'id' | 'title'> | undefined): string {
  return [
    '# Overview',
    'An invented page text for the demo: it checks **who** asks and *from where*, as [the guide](https://example.com/guide) says.',
    '## Steps',
    '1. Plan\n2. Roll **out**\n3. Review',
    `See ${other ? `[${other.title}](obsn:${other.id})` : 'another page'} for the background.`,
    '- Check the user\n    - with a second factor\n- Check the device',
    '- [ ] ask the network team\n- [x] read the guide',
    '| Name | Use |\n| --- | --- |\n| Proxy | checks every request |\n| `vpn` | the old way |',
    '## Your notes',
    'My own words stay.',
  ].join('\n\n')
}

export interface DemoServer {
  /** The demo's model as it stands now (edits and tags change it). */
  model: () => GraphModel
  editPage: (req: PageEditRequest, log: (s: string) => void) => Promise<void>
  linkMention: (a: GraphPage, b: GraphPage, log: (s: string) => void) => Promise<void>
  tagPages: (ids: string[], add: string[], remove: string[], log: (s: string) => void) => Promise<void>
  loadBody: (id: string) => Promise<PageBodyResult>
}

/** The stand-ins over `start`, steered by the page's URL parameters `params`. */
export function createDemoServer(params: URLSearchParams, start: GraphModel): DemoServer {
  let model = start

  /** After `ms`, fails with `message` when ?<param>=fail, else runs `ok` and resolves. */
  const afterOrFail = (param: string, message: string, ms: number, ok: () => void) =>
    new Promise<void>((resolve, reject) =>
      setTimeout(() => {
        if (params.get(param) === 'fail') return reject(new Error(message))
        ok()
        resolve()
      }, ms),
    )

  return {
    model: () => model,
    // Edit: the title and summary change in the demo's own model. ?edit=fail shows the error in the form.
    editPage: (req, log) =>
      afterOrFail('edit', WRITER_ELSEWHERE, 400, () => {
        model = { ...model, pages: model.pages.map((p) => (p.id === req.id ? { ...p, title: req.title ?? p.title, summary: req.summary ?? p.summary } : p)) }
        log(`Edit: ${JSON.stringify(req)}`)
      }),
    // "Link it" on a mention. ?link=fail shows the error; ?link=slow keeps the button busy for a minute.
    linkMention: (a, b, log) => afterOrFail('link', WRITER_ELSEWHERE, params.get('link') === 'slow' ? 60_000 : 400, () => log(`Link it: ${a.title} → ${b.title}`)),
    // Tags change in the demo's own model. ?tag=fail shows the error.
    tagPages: async (ids, add, remove, log) => {
      if (params.get('tag') === 'fail') throw new Error(WRITER_ELSEWHERE)
      model = { ...model, pages: model.pages.map((p) => (ids.includes(p.id) ? { ...p, tags: [...p.tags.filter((t) => !remove.includes(t)), ...add.filter((t) => !p.tags.includes(t))] } : p)) }
      log(`Tag ${ids.length} page(s): +[${add.join(', ')}] -[${remove.join(', ')}]`)
    },
    // The page's text. ?body=fail|empty|long shows the other states.
    loadBody: (id) =>
      new Promise((resolve, reject) =>
        setTimeout(() => {
          const body = params.get('body')
          if (body === 'fail') return reject(new Error('The page could not be read from OneNote. Try again.'))
          if (body === 'empty') return resolve({ markdown: '', truncated: false })
          resolve({ truncated: body === 'long', markdown: demoPageText(model.pages.find((p) => p.id !== id)) })
        }, 300),
      ),
  }
}
