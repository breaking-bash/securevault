import { invoke } from '@tauri-apps/api/core'

export interface AppInfo {
  name: string
  version: string
}

export type VaultStatus = 'no_account' | 'locked' | 'unlocked'

export interface LoginItem {
  title: string
  username: string
  password: string
  url: string
}

// The frontend performs no cryptography; it only calls narrow Rust commands.
export const getAppInfo = () => invoke<AppInfo>('app_info')
export const vaultStatus = () => invoke<VaultStatus>('vault_status')
export const createAccount = (password: string) =>
  invoke<string>('create_account', { password })
export const unlock = (password: string, secretKey: string) =>
  invoke<void>('unlock', { password, secretKey })
export const lock = () => invoke<void>('lock')
export const listItems = () => invoke<string[]>('list_items')
export const deleteItem = (id: string) => invoke<void>('delete_item', { id })
export const generatePassword = (length: number, symbols: boolean) =>
  invoke<string>('generate_password', { length, symbols })

export async function getItem(id: string): Promise<LoginItem> {
  const raw = await invoke<string>('get_item', { id })
  return JSON.parse(raw) as LoginItem
}

export const saveItem = (item: LoginItem, id?: string) =>
  invoke<string>('save_item', { id: id ?? null, payload: JSON.stringify(item) })
