import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '../../src/styles/tokens.css'
import './styles/app.css'
import { App } from './App'
import { installDisabledGuard } from './components/disabledGuard'
import { applyTheme, getStoredTheme } from './model/preferences'

// Before the first render, so a chosen theme never flashes the other one.
applyTheme(getStoredTheme())
// A press on a control marked aria-disabled="true" is ignored, window-wide (components/disabledGuard.ts).
installDisabledGuard(window)

const root = document.getElementById('root')
if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
}
