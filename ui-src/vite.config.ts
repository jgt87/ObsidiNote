/// <reference types="vitest/config" />
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'

// The favicons have one source: the repo's assets/ folder (made by tools/make-icon.py).
const assetsDir = fileURLToPath(new URL('../assets/', import.meta.url))
const favicons: Plugin = {
  name: 'obsidinote-favicons',
  apply: 'build',
  generateBundle() {
    for (const fileName of ['favicon.svg', 'favicon.ico']) {
      this.emitFile({ type: 'asset', fileName, source: readFileSync(assetsDir + fileName) })
    }
  },
}

// Built into ../ui, which obsidinote.ps1 serves (lib/Server.psm1); the user's PC never runs Node.
// Dev server: its own port 5190; /api goes to a running ObsidiNote on 8767 with that server's
// own Origin and Host, which are the only ones it accepts.
export default defineConfig({
  plugins: [react(), favicons],
  base: './',
  // A CI runner was 9 times slower than this PC on one run (v0.10.0's tag run, 2026-11-15) and the
  // geometry tests that lay out 1,000 to 5,000 pages ran past vitest's 5 s default. This is the
  // time a test may take before it counts as hung; how fast code is stays pinned by growth tests
  // (src/testing/scaling.ts), never by this number.
  test: { testTimeout: 30000 },
  build: { outDir: '../ui', emptyOutDir: true, assetsInlineLimit: 8192 },
  server: {
    port: 5190,
    strictPort: true,
    fs: { allow: ['..'] },
    proxy: { '/api': { target: 'http://127.0.0.1:8767', changeOrigin: true, headers: { origin: 'http://127.0.0.1:8767' } } },
  },
})
