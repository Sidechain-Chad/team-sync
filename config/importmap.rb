# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "sortablejs" # @1.15.6
pin "@rails/request.js", to: "@rails--request.js.js" # @0.0.13

pin "@tiptap/core", to: "https://esm.sh/@tiptap/core"
pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit"
pin "@tiptap/extension-link", to: "https://esm.sh/@tiptap/extension-link"
pin "@tiptap/extension-image", to: "https://esm.sh/@tiptap/extension-image"
pin "@tiptap/extension-placeholder", to: "https://esm.sh/@tiptap/extension-placeholder"
pin "@tiptap/pm", to: "https://esm.sh/@tiptap/pm"
pin "@tiptap/extensions", to: "https://esm.sh/@tiptap/extensions"
