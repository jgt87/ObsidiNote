// Markdown export (user, 2026-11-13): POST /api/export answers with the file itself (one .md for a
// page, a .zip for a topic or everything). The file is handed to the browser as a download the
// person asked for; nothing is kept here. Every call carries X-ObsidiNote: 1, which the server
// requires (so a plain link cannot be used).

export type ExportScope = 'page' | 'topic' | 'all'

export interface ExportRequest {
  scope: ExportScope
  vault?: string
  notebook?: string
  page?: string
  topic?: string
}

export interface ExportSource {
  kind: 'vault' | 'notebook'
  id: string
}

/** The source part of an export request: a vault by its vault id, a notebook by its id. */
export function exportSourceOf(source: ExportSource): Pick<ExportRequest, 'vault' | 'notebook'> {
  if (!source.id) return {}
  return source.kind === 'notebook' ? { notebook: source.id } : { vault: source.id }
}

/** The file name from Content-Disposition: filename* (UTF-8) first, then filename, else the fallback.
 *  Path parts are never kept. */
export function fileNameFrom(header: string | null, fallback: string): string {
  let name = ''
  if (header) {
    const star = /filename\*\s*=\s*UTF-8''([^;]+)/i.exec(header)
    if (star) {
      try {
        name = decodeURIComponent(star[1].trim())
      } catch {
        name = ''
      }
    }
    if (!name) {
      const plain = /filename\s*=\s*"([^"]*)"|filename\s*=\s*([^;]+)/i.exec(header)
      if (plain) name = (plain[1] ?? plain[2] ?? '').trim()
    }
  }
  name = name.split(/[\\/]/).pop() ?? ''
  return name || fallback
}

/** What the person sees after an export, or why it did not work. */
export function exportDoneText(name: string): string {
  return `Downloaded ${name}. It is a copy: ObsidiNote keeps nothing of it.`
}

export function saveBlob(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.rel = 'noopener'
  document.body.appendChild(a)
  a.click()
  a.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

export async function exportMarkdown(req: ExportRequest, fetcher: typeof fetch = fetch, save: (b: Blob, n: string) => void = saveBlob): Promise<string> {
  let res: Response
  try {
    res = await fetcher('/api/export', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-ObsidiNote': '1' },
      body: JSON.stringify(req),
      cache: 'no-store',
    })
  } catch {
    throw new Error('ObsidiNote is not answering. Is it still running?')
  }
  if (res.status !== 200) {
    const body: unknown = await res.json().catch(() => null)
    const msg = body && typeof body === 'object' && 'error' in body ? String((body as { error: unknown }).error) : `The export did not work (${res.status}).`
    throw new Error(msg)
  }
  const name = fileNameFrom(res.headers.get('Content-Disposition'), req.scope === 'page' ? 'page.md' : 'export.zip')
  save(await res.blob(), name)
  return name
}
