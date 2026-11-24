import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Notice } from './Notice'

interface Props {
  /** What this region is, for the message ("the side bar", "this view"). */
  region: string
  children: ReactNode
  /** Changes when the region shows something else (another view): a failed region tries again. */
  resetKey?: string
}

/** One per region of the window (side bar, the view, the switcher, the dialogs): an error while
 *  drawing one region leaves the others usable (audit 2026-11-24: one render error blanked the
 *  whole window). The message is the error box with a way to try again; nothing is written to disk. */
export class ErrorBoundary extends Component<Props, { error: Error | null; key: string | undefined }> {
  state = { error: null as Error | null, key: this.props.resetKey }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  static getDerivedStateFromProps(props: Props, state: { error: Error | null; key: string | undefined }) {
    return props.resetKey !== state.key ? { error: null, key: props.resetKey } : null
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // The console only (no content: the message and where it failed).
    console.error(`ObsidiNote: ${this.props.region} failed to draw`, error, info.componentStack)
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children
    return (
      <Notice
        error
        title={`Something went wrong in ${this.props.region}`}
        actions={
          <button type="button" className="btn" onClick={() => this.setState({ error: null })}>
            Draw {this.props.region} again
          </button>
        }
      >
        <p>{error.message || 'An unexpected error.'} The rest of the window still works. If it happens again, reload the window (Ctrl+R).</p>
      </Notice>
    )
  }
}
