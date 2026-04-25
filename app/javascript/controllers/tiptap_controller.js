import { Controller } from "@hotwired/stimulus"
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Placeholder from '@tiptap/extension-placeholder'

export default class extends Controller {
  static targets = [ "element", "input", "boldButton", "italicButton", "linkButton", "imageButton" ]

  connect() {
    this.editor = new Editor({
      element: this.elementTarget,
      extensions: [
        StarterKit,
        Link.configure({ openOnClick: false }),
        Image,
        Placeholder.configure({ placeholder: 'Add a more detailed description...' }),
      ],
      content: this.inputTarget.value,
      onUpdate: ({ editor }) => {
        this.inputTarget.value = editor.getHTML()
        this.updateToolbarState()
      },
      onSelectionUpdate: () => {
        this.updateToolbarState()
      },
    })
    this.updateToolbarState()

    // Close the editor when clicking outside it. Trello-style.
    // Use mousedown so we react before any click handler tries to do
    // something with the editor's frame.
    this.boundOutsideClick = this.outsideClick.bind(this)
    setTimeout(() => {
      document.addEventListener("mousedown", this.boundOutsideClick)
    }, 0)
  }

  disconnect() {
    document.removeEventListener("mousedown", this.boundOutsideClick)
    this.editor.destroy()
  }

  outsideClick(event) {
    // Walk up to the enclosing form — that's the real edit boundary.
    // The Save / Cancel buttons live outside the tiptap container but
    // inside the form, so they should NOT trigger an outside-click cancel.
    const formEl = this.element.closest('form')
    const boundary = formEl || this.element

    if (boundary.contains(event.target)) return

    // Ignore clicks inside any popover (labels, members, etc.)
    if (event.target.closest('[data-dropdown-target="menu"]')) return

    this.cancelEdit()
  }

  cancelEdit() {
    // Find the Cancel link in the form and click it.
    // The link points back to the card show page, which will swap the
    // turbo-frame back to the read-only description partial.
    const cancelLink = this.element.closest('form')?.querySelector('a[href*="/cards/"]')
    if (cancelLink) cancelLink.click()
  }

  toggleBold() {
    this.editor.chain().focus().toggleBold().run()
  }

  toggleItalic() {
    this.editor.chain().focus().toggleItalic().run()
  }

  toggleLink() {
    const previousUrl = this.editor.getAttributes('link').href
    const url = window.prompt('URL', previousUrl)

    if (url === null) {
      return
    }

    if (url === '') {
      this.editor.chain().focus().extendMarkRange('link').unsetLink().run()
      return
    }

    this.editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
  }

  addImage() {
    const url = window.prompt('URL')

    if (url) {
      this.editor.chain().focus().setImage({ src: url }).run()
    }
  }

  updateToolbarState() {
    if (!this.editor) return

    this.updateButtonState(this.boldButtonTarget, 'bold')
    this.updateButtonState(this.italicButtonTarget, 'italic')
    this.updateButtonState(this.linkButtonTarget, 'link')
  }

  updateButtonState(button, attribute) {
    if (this.editor.isActive(attribute)) {
      button.classList.add('bg-gray-200', 'text-blue-600')
      button.classList.remove('text-gray-600')
    } else {
      button.classList.remove('bg-gray-200', 'text-blue-600')
      button.classList.add('text-gray-600')
    }
  }
}
