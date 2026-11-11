import { invoke } from '@tauri-apps/api/core'

export interface AppInfo {
  name: string
  version: string
}

// The frontend performs no cryptography; it only calls narrow Rust commands.
export function getAppInfo(): Promise<AppInfo> {
  return invoke<AppInfo>('app_info')
}
