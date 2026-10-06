import { registerController } from 'galvani'

// The boot script in `Base` applied the stored choice before first paint;
// this only flips it and remembers the flip.
const STORAGE_KEY = 'aperture-theme'
const CHROME = { dark: '#0a0c10', light: '#f4f5f7' }

registerController('theme', () => ({
  toggle() {
    const root = document.documentElement
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark'
    root.dataset.theme = next
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', CHROME[next])
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {
      // Storage refused (private mode): the switch still holds for this page.
    }
  },
}))
