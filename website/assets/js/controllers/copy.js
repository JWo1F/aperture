import { registerController, useEffect, useRef, useTarget } from 'galvani'

// Copies the listing's text without what is marked decorative (the `$`
// prompts), and shows "Copied" for a moment.
registerController('copy', () => {
  const source = useTarget('source')
  const idle = useTarget('idle')
  const done = useTarget('done')
  const timer = useRef(null)

  useEffect(() => () => clearTimeout(timer.current), [])

  return {
    async copy() {
      const clone = source.cloneNode(true)
      clone.querySelectorAll('[aria-hidden="true"]').forEach(node => node.remove())
      await navigator.clipboard.writeText(clone.textContent)
      idle.hidden = true
      done.hidden = false
      clearTimeout(timer.current)
      timer.current = setTimeout(() => {
        idle.hidden = false
        done.hidden = true
      }, 1600)
    },
  }
})
