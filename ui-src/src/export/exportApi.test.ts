import { describe, expect, it, vi } from 'vitest'
import { exportMarkdown, exportSourceOf, fileNameFrom } from './exportApi'

describe('exportSourceOf', () => {
  it('names a vault by its vault id and a notebook by its id', () => {
    expect(exportSourceOf({ kind: 'vault', id: 'abc-1' })).toEqual({ vault: 'abc-1' })
    expect(exportSourceOf({ kind: 'notebook', id: '{N1}' })).toEqual({ notebook: '{N1}' })
    expect(exportSourceOf({ kind: 'vault', id: '' })).toEqual({})
  })
})

describe('fileNameFrom', () => {
  it('prefers the UTF-8 name, then the plain one, else the fallback; never a path', () => {
    expect(fileNameFrom(`attachment; filename="Caf_.md"; filename*=UTF-8''Caf%C3%A9.md`, 'x')).toBe('Café.md')
    expect(fileNameFrom('attachment; filename="Work - Markdown.zip"', 'x')).toBe('Work - Markdown.zip')
    expect(fileNameFrom(`attachment; filename*=UTF-8''..%2F..%2Fevil.md`, 'x')).toBe('evil.md')
    expect(fileNameFrom(null, 'export.zip')).toBe('export.zip')
  })
})

describe('exportMarkdown', () => {
  it('posts the request with the app header and saves the answer under its name', async () => {
    const fetcher = vi.fn(async () => new Response('---\n', { status: 200, headers: { 'Content-Disposition': `attachment; filename="p.md"; filename*=UTF-8''Page.md` } }))
    const save = vi.fn()
    const name = await exportMarkdown({ scope: 'page', vault: 'v1', page: 'p1' }, fetcher as unknown as typeof fetch, save)
    expect(name).toBe('Page.md')
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('/api/export')
    expect((init.headers as Record<string, string>)['X-ObsidiNote']).toBe('1')
    expect(JSON.parse(String(init.body))).toEqual({ scope: 'page', vault: 'v1', page: 'p1' })
    expect(save).toHaveBeenCalledTimes(1)
  })
  it('throws the server reason and saves nothing', async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ error: 'That topic has no pages.' }), { status: 404 }))
    const save = vi.fn()
    await expect(exportMarkdown({ scope: 'topic', topic: 'X' }, fetcher as unknown as typeof fetch, save)).rejects.toThrow('That topic has no pages.')
    expect(save).not.toHaveBeenCalled()
  })
})
