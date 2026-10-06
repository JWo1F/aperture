import { registerController, useState, useTargets } from 'galvani'

// One of several screenshots behind a segmented control. Panels cross-fade
// through `data-off`, so every image stays in the grid cell and the frame
// never changes height.
registerController('showcase', () => {
  const tabs = useTargets('tab')
  const panels = useTargets('panel')
  const captions = useTargets('caption')
  const [current, setCurrent] = useState(() => Math.max(0, tabs.findIndex(t => t.getAttribute('aria-selected') === 'true')))

  tabs.forEach((tab, i) => tab.setAttribute('aria-selected', String(i === current)))
  panels.forEach((panel, i) => panel.toggleAttribute('data-off', i !== current))
  captions.forEach((caption, i) => (caption.hidden = i !== current))

  return {
    select: event => setCurrent(event.params.index),
  }
})
