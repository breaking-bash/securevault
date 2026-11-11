import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'

vi.mock('./api', () => ({
  getAppInfo: vi.fn().mockResolvedValue({ name: 'securevault', version: '0.1.0' }),
}))

import App from './App'

describe('App', () => {
  it('renders the scaffold notice and core info', async () => {
    render(<App />)
    expect(screen.getByRole('status').textContent).toContain('No encryption')
    expect(await screen.findByText(/securevault v0.1.0/)).toBeTruthy()
  })
})
