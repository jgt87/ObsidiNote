// The app's three dialogs (App.tsx): Settings, New vault and Set up a vault. One is open at a time.
import type { NotebookSummary } from '../api'
import { activeVaultNotice } from '../model/notebooks'
import type { VaultSettings } from '../model/vaultSettings'
import { NewVaultDialog } from './NewVaultDialog'
import { SetUpVaultDialog } from './SetUpVaultDialog'
import { SettingsDialog } from './SettingsDialog'

export type AppDialog = 'new-vault' | 'set-up' | 'settings' | null

interface Props {
  dialog: AppDialog
  onClose: () => void
  notebooks: NotebookSummary[]
  /** The shown notebook: the one Set up makes a vault. */
  shown: NotebookSummary | undefined
  /** The running app's version, top right in Settings. */
  version: string
  onSettingsSaved: (s: VaultSettings) => void
  /** A tag was renamed or removed, or settings were saved: the graph reads its pages again. */
  onTagsChanged: () => void
  /** A vault the server just made active (made or set up), with what to say about it. */
  onAdopt: (id: string, notice: string) => void
}

export function AppDialogs({ dialog, onClose, notebooks, shown, version, onSettingsSaved, onTagsChanged, onAdopt }: Props) {
  if (dialog === 'settings') return <SettingsDialog onClose={onClose} onSaved={onSettingsSaved} onTagsChanged={onTagsChanged} version={version} />
  if (dialog === 'new-vault') return <NewVaultDialog notebooks={notebooks} onClose={onClose} onMade={(r) => onAdopt(r.id, activeVaultNotice(r.name, r.warning))} />
  if (dialog === 'set-up' && shown) return <SetUpVaultDialog id={shown.id} name={shown.name} onClose={onClose} onDone={(r) => onAdopt(r.id, activeVaultNotice(r.name))} />
  return null
}
