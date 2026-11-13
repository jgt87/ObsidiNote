// Display helpers for the Add result. Pure (tests: format.test.ts).
import { plural } from '../model/format'
import type { Chip, LinkUpdate, PlacedPage } from './types'

/** "Security/Networking" -> ["Security", "Networking"]. */
export function topicParts(path: string): string[] {
  return path
    .split('/')
    .map((p) => p.trim())
    .filter(Boolean)
}

/** "Security/Networking" -> "Security / Networking". */
export function formatTopicPath(path: string): string {
  return topicParts(path).join(' / ')
}

/** Where the page sits in the central index: its first topic path, then the title. */
export function placementParts(page: PlacedPage): string[] {
  const head = page.topicPath ? topicParts(page.topicPath) : ['Unfiled']
  return [...head, page.title]
}

export function formatOneNotePath(page: PlacedPage): string {
  return page.oneNotePath.join(' › ')
}

/** 3240 -> "3.2 s"; under a second -> "0.4 s". */
export function formatSeconds(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return ''
  return `${(ms / 1000).toFixed(1)} s`
}

export function clampStrength(n: number): 1 | 2 | 3 {
  const s = Math.round(Number(n) || 1)
  return s >= 3 ? 3 : s <= 1 ? 1 : 2
}

export function strengthLabel(n: number): string {
  return `Strength ${clampStrength(n)} of 3`
}

export function chipLabel(chip: Chip): string {
  switch (chip.kind) {
    case 'type':
      return `type: ${chip.label}`
    case 'alias':
      return `alias: ${chip.label}`
    case 'new-topic':
      return `new topic: ${chip.label}`
    default:
      return `topic: ${chip.label}`
  }
}

export function backlinksLine(n: number): string {
  if (n <= 0) return 'No backlinks were added'
  return `Backlinks added to ${plural(n, 'page')} (in their "Linked from" block only)`
}

/** The heading of a result screen. */
export function resultHeading(status: string, title: string): string {
  switch (status) {
    case 'added':
      return `Added: ${title}`
    case 'updated':
      return `Updated: ${title}`
    case 'unchanged':
      return `No changes: ${title}`
    case 'kept':
      return `Kept your summary: ${title}`
    case 'needs-confirmation':
      return `Update: ${title}`
    case 'could-not-update':
      return `Could not update: ${title}`
    case 'ask-instead':
      return 'This looks like a question'
    case 'waiting':
      return 'Waiting for Copilot'
    case 'still-waiting':
    case 'mismatch':
    case 'invalid':
      return 'Not added yet'
    default:
      return 'Not added'
  }
}

export interface FieldChange {
  label: string
  old: string
  new: string
}

/** The fields of a link summary that changed, for the old vs new view. */
export function changedFields(u: LinkUpdate): FieldChange[] {
  const o = u.old
  const n = u.new
  if (!n) return []
  const rows: [string, keyof NonNullable<LinkUpdate['old']>][] = [
    ['Title', 'title'],
    ['Kind', 'kind'],
    ['Where', 'where'],
    ['Use it for', 'useFor'],
    ['Sensitivity', 'sensitivity'],
  ]
  const norm = (s: unknown) => String(s ?? '').replace(/\s+/g, ' ').trim().toLowerCase()
  return rows
    .filter(([, k]) => norm(o?.[k]) !== norm(n[k]))
    .map(([label, k]) => ({ label, old: String(o?.[k] ?? ''), new: String(n[k] ?? '') }))
}
