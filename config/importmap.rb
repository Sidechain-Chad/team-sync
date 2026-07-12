# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "sortablejs" # @1.15.6
pin "@rails/request.js", to: "@rails--request.js.js" # @0.0.13

# Pinned to an exact version (matching the flatpickr pin below) rather
# than a bare "latest" URL — an unversioned esm.sh pin drifts silently
# whenever tiptap cuts a new release.
#
# @tiptap/pm is deliberately NOT pinned here: nothing in app/javascript
# imports it directly, and it can't be — its package.json only exposes
# subpath exports (./model, ./state, ./commands, etc.), no root entry
# point, so esm.sh 404s on the bare specifier ("could not resolve build
# entry"). The importmap's default modulepreload was fetching it on every
# page regardless of whether tiptap was even in use, which is exactly
# where that console error was coming from.
pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@3.27.3"
pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit@3.27.3"
pin "@tiptap/extension-link", to: "https://esm.sh/@tiptap/extension-link@3.27.3"
pin "@tiptap/extension-image", to: "https://esm.sh/@tiptap/extension-image@3.27.3"
pin "@tiptap/extension-placeholder", to: "https://esm.sh/@tiptap/extension-placeholder@3.27.3"
pin "@tiptap/extensions", to: "https://esm.sh/@tiptap/extensions@3.27.3"

pin "flatpickr", to: "https://esm.sh/flatpickr@4.6.13"
