// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Turbo Drive swaps in the new <body> on every visit but never touches the
// existing <html> element or its attributes — so data-theme, rendered
// server-side by ApplicationHelper#current_theme (see application.html.erb),
// stays pinned to whatever the PREVIOUS page had. That is invisible on most
// navigations because the resolved theme rarely changes mid-session, but it is
// exactly wrong on sign-in: the signed-out page renders data-theme="light"
// (no stored preference to read), and the redirect Turbo follows into the
// dashboard renders a body that already reflects a stored "dark" preference
// while leaving the signed-out "light" attribute stuck on <html> — a dark-
// theme user then sees a light page under a switcher correctly showing "Dark"
// selected, until a hard reload re-parses the whole document from scratch.
//
// `newBody.ownerDocument` is the document Turbo just parsed from the
// response, so its <html> carries the value the server resolved for THIS
// response — the same canonical source current_theme already feeds the
// switcher from. Copying it onto the live <html> on every render keeps the
// two permanently in sync instead of patching the sign-in transition alone;
// `dataset.theme` is empty (falsy) for frame-level renders that don't carry a
// real layout, so this is a no-op then rather than clobbering anything.
document.addEventListener("turbo:before-render", (event) => {
  const theme = event.detail.newBody.ownerDocument.documentElement.dataset.theme
  if (theme) document.documentElement.dataset.theme = theme
})
