import { Controller } from "@hotwired/stimulus"
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Placeholder from '@tiptap/extension-placeholder'

export default class extends Controller {
  static targets = [
    "element", "input",
    "toolbar", "headingMenu", "moreMenu", "linkMenu", "imageMenu", "insertMenu"
  ]

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
      },
    })

    // Belt-and-braces: when the form submits, copy the editor's current
    // HTML into the hidden input. onUpdate normally handles this on every
    // keystroke, but this guarantees we never submit a stale value.
    this.formEl = this.element.closest('form')
    if (this.formEl) {
      this.boundFormSubmit = this.syncOnSubmit.bind(this)
      this.formEl.addEventListener('submit', this.boundFormSubmit)
    }

    // Close any open toolbar submenu when clicking elsewhere on the page.
    this.boundCloseMenus = this.closeAllMenus.bind(this)
    document.addEventListener('mousedown', this.boundCloseMenus)
  }

  disconnect() {
    if (this.formEl && this.boundFormSubmit) {
      this.formEl.removeEventListener('submit', this.boundFormSubmit)
    }
    document.removeEventListener('mousedown', this.boundCloseMenus)
    if (this.editor) this.editor.destroy()
  }

  syncOnSubmit() {
    if (this.editor) {
      this.inputTarget.value = this.editor.getHTML()
    }
  }

  // -- Heading menu --
  toggleHeadingMenu(e) { e.stopPropagation(); this.toggleMenu(this.headingMenuTarget) }
  setHeading(e) {
    e.preventDefault()
    const level = parseInt(e.currentTarget.dataset.level, 10)
    if (level === 0) {
      this.editor.chain().focus().setParagraph().run()
    } else {
      this.editor.chain().focus().toggleHeading({ level }).run()
    }
    this.closeAllMenus()
  }

  // -- Basic formatting --
  toggleBold()       { this.editor.chain().focus().toggleBold().run() }
  toggleItalic()     { this.editor.chain().focus().toggleItalic().run() }
  toggleStrike()     { this.editor.chain().focus().toggleStrike().run() }
  toggleCode()       { this.editor.chain().focus().toggleCode().run() }
  clearFormatting()  { this.editor.chain().focus().clearNodes().unsetAllMarks().run() }

  // -- Lists --
  toggleBulletList()  { this.editor.chain().focus().toggleBulletList().run() }
  toggleOrderedList() { this.editor.chain().focus().toggleOrderedList().run() }

  // -- More menu --
  toggleMoreMenu(e) { e.stopPropagation(); this.toggleMenu(this.moreMenuTarget) }

  // -- Link menu --
  toggleLinkMenu(e) { e.stopPropagation(); this.toggleMenu(this.linkMenuTarget) }
  setLink() {
    const url  = document.getElementById('link-url-input')?.value
    const text = document.getElementById('link-text-input')?.value
    if (!url) return
    if (text) {
      this.editor.chain().focus().insertContent(`<a href="${url}">${text}</a>`).run()
    } else {
      this.editor.chain().focus().setLink({ href: url }).run()
    }
    this.closeAllMenus()
  }

  // -- Image menu --
  toggleImageMenu(e) { e.stopPropagation(); this.toggleMenu(this.imageMenuTarget) }
  setImage() {
    const url = document.getElementById('image-url-input')?.value
    if (!url) return
    this.editor.chain().focus().setImage({ src: url }).run()
    this.closeAllMenus()
  }

  // -- Insert menu --
  toggleInsertMenu(e)  { e.stopPropagation(); this.toggleMenu(this.insertMenuTarget) }
  addDivider()         { this.editor.chain().focus().setHorizontalRule().run(); this.closeAllMenus() }
  toggleBlockquote()   { this.editor.chain().focus().toggleBlockquote().run(); this.closeAllMenus() }
  toggleCodeBlock()    { this.editor.chain().focus().toggleCodeBlock().run(); this.closeAllMenus() }

  // -- Helpers --
  toggleMenu(menuEl) {
    const wasHidden = menuEl.classList.contains('hidden')
    this.closeAllMenus()
    if (wasHidden) menuEl.classList.remove('hidden')
  }

  closeAllMenus(event) {
    // If event came from inside a menu, leave it alone (button inside menu).
    if (event && event.target.closest('[data-tiptap-target$="Menu"]')) return

    const menus = [
      this.hasHeadingMenuTarget && this.headingMenuTarget,
      this.hasMoreMenuTarget    && this.moreMenuTarget,
      this.hasLinkMenuTarget    && this.linkMenuTarget,
      this.hasImageMenuTarget   && this.imageMenuTarget,
      this.hasInsertMenuTarget  && this.insertMenuTarget,
    ].filter(Boolean)

    menus.forEach(m => m.classList.add('hidden'))
  }
}
