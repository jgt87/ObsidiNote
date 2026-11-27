// Types for the parts of check-design-rules.mjs that src/testing/checkDesignRules.test.ts imports.
// The script stays plain JavaScript (node runs it as is); keep this file in step with its exports.

interface FixturePage { id: string; title: string; url?: string }

export function answer(path: string): Record<string, unknown> | null
export function bodyShownRight(body: { shown: boolean; headings?: number; lists?: number; table?: boolean; pageLinks?: number; web?: string[]; html?: boolean; scroll?: boolean }): boolean
export function readFailedRight(err: { text: string; role: string; retry: string[]; links: number }): boolean
export function composerRowRight(row: { n: number; spread: number; clip?: string | null }): boolean
export function citationsRight(cites: { tag?: string; href?: string }[]): boolean
export function askAnswerFixture(pages: FixturePage[]): {
  answer: { intent: string; sources: { n: number; id: string; url: string }[]; answer: { paragraphs: { sentences: { cites: number[] }[] }[] } }
  target: FixturePage
}
export const RULES: ((t: unknown) => Promise<void>)[]
