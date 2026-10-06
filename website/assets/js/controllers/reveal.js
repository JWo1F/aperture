import { registerController, useEffect } from 'galvani'

// Fades `.reveal` blocks in as they first scroll into view. The hidden state
// is gated on the `js` class the boot script sets, so without script the
// page is simply all there.
registerController('reveal', element => {
  useEffect(() => {
    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue
          entry.target.classList.add('is-in')
          observer.unobserve(entry.target)
        }
      },
      { rootMargin: '0px 0px -12% 0px' },
    )
    element.querySelectorAll('.reveal').forEach(node => observer.observe(node))
    return () => observer.disconnect()
  }, [])

  return {}
})
