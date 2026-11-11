import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('./api', () => ({
  vaultStatus: vi.fn(),
  createAccount: vi.fn().mockResolvedValue('AAAA-BBBB'),
  unlock: vi.fn().mockResolvedValue(undefined),
  lock: vi.fn().mockResolvedValue(undefined),
  listItems: vi.fn().mockResolvedValue(['1']),
  getItem: vi.fn().mockResolvedValue({
    title: 'Bank',
    username: 'me',
    password: 'hunter2',
    url: '',
  }),
  saveItem: vi.fn(),
  deleteItem: vi.fn(),
  generatePassword: vi.fn(),
}))

import * as api from './api'
import App from './App'

const status = vi.mocked(api.vaultStatus)

describe('App', () => {
  afterEach(cleanup)
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.createAccount).mockResolvedValue('AAAA-BBBB')
  })

  it('always shows the pre-release warning', async () => {
    status.mockResolvedValue('locked')
    render(<App />)
    expect(screen.getByRole('status').textContent).toContain('not been independently reviewed')
    expect(await screen.findByRole('heading', { name: 'Unlock' })).toBeTruthy()
  })

  it('shows the Secret Key once and requires acknowledgement', async () => {
    status.mockResolvedValue('no_account')
    render(<App />)
    fireEvent.change(await screen.findByLabelText(/Master password/), {
      target: { value: 'long enough pw' },
    })
    fireEvent.click(screen.getByText('Create'))
    expect(await screen.findByLabelText('secret key')).toBeTruthy()
    const cont = screen.getByText('Continue') as HTMLButtonElement
    expect(cont.disabled).toBe(true)
    fireEvent.click(screen.getByLabelText(/stored my Secret Key/))
    expect(cont.disabled).toBe(false)
  })

  it('hides passwords until revealed and locks on demand', async () => {
    status.mockResolvedValue('unlocked')
    render(<App />)
    expect(await screen.findByText('Bank')).toBeTruthy()
    expect(screen.queryByText('hunter2')).toBeNull()
    fireEvent.click(screen.getByText('Reveal'))
    expect(screen.getByText('hunter2')).toBeTruthy()
    status.mockResolvedValue('locked')
    fireEvent.click(screen.getByText('Lock'))
    expect(await screen.findByRole('heading', { name: 'Unlock' })).toBeTruthy()
    expect(api.lock).toHaveBeenCalled()
  })
})
