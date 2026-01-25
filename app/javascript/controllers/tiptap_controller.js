import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import Placeholder from "@tiptap/extension-placeholder"

export default class extends Controller {
  static targets = [
    "element", "input", "toolbar",
    "headingMenu", "linkMenu", "imageMenu", "moreMenu", "insertMenu"
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
        this.updateToolbarState()
      },
      onSelectionUpdate: () => {
        this.updateToolbarState()
      },
    })
    this.updateToolbarState()
  }

  disconnect() {
    this.editor.destroy()
  }

  // --- 1. Basic Formatting ---
  toggleBold() { this.editor.chain().focus().toggleBold().run() }
  toggleItalic() { this.editor.chain().focus().toggleItalic().run() }

  // --- 2. Headings ---
  toggleHeadingMenu() {
    this.closeAllMenusExcept("headingMenu")
    this.headingMenuTarget.classList.toggle("hidden")
  }

  setHeading(event) {
    const level = parseInt(event.currentTarget.dataset.level)
    level === 0
      ? this.editor.chain().focus().setParagraph().run()
      : this.editor.chain().focus().toggleHeading({ level: level }).run()
    this.headingMenuTarget.classList.add("hidden")
  }

  // --- 3. Lists ---
  toggleBulletList() { this.editor.chain().focus().toggleBulletList().run() }
  toggleOrderedList() { this.editor.chain().focus().toggleOrderedList().run() }

  // --- 4. Links ---
  toggleLinkMenu() {
    this.closeAllMenusExcept("linkMenu")
    this.linkMenuTarget.classList.toggle("hidden")
  }

  setLink(event) {
    event.preventDefault()
    const url = document.getElementById('link-url-input').value
    if (url) {
      this.editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
    }
    this.linkMenuTarget.classList.add("hidden")
    this.clearInputs(['link-url-input', 'link-text-input'])
  }

  // --- 5. Images (New) ---
  toggleImageMenu() {
    this.closeAllMenusExcept("imageMenu")
    this.imageMenuTarget.classList.toggle("hidden")
  }

  setImage(event) {
    event.preventDefault()
    const url = document.getElementById('image-url-input').value
    if (url) {
      this.editor.chain().focus().setImage({ src: url }).run()
    }
    this.imageMenuTarget.classList.add("hidden")
    this.clearInputs(['image-url-input'])
  }

  // --- 6. More Options (...) (New) ---
  toggleMoreMenu() {
    this.closeAllMenusExcept("moreMenu")
    this.moreMenuTarget.classList.toggle("hidden")
  }

  toggleStrike() {
    this.editor.chain().focus().toggleStrike().run()
    this.moreMenuTarget.classList.add("hidden")
  }

  toggleCode() {
    this.editor.chain().focus().toggleCode().run()
    this.moreMenuTarget.classList.add("hidden")
  }

  clearFormatting() {
    this.editor.chain().focus().unsetAllMarks().run()
    this.moreMenuTarget.classList.add("hidden")
  }

  // --- 7. Insert Elements (+) (New) ---
  toggleInsertMenu() {
    this.closeAllMenusExcept("insertMenu")
    this.insertMenuTarget.classList.toggle("hidden")
  }

  addDivider() {
    this.editor.chain().focus().setHorizontalRule().run()
    this.insertMenuTarget.classList.add("hidden")
  }

  toggleBlockquote() {
    this.editor.chain().focus().toggleBlockquote().run()
    this.insertMenuTarget.classList.add("hidden")
  }

  toggleCodeBlock() {
    this.editor.chain().focus().toggleCodeBlock().run()
    this.insertMenuTarget.classList.add("hidden")
  }

  // --- Helpers ---
  closeAllMenusExcept(targetName) {
    const menus = ["headingMenu", "linkMenu", "imageMenu", "moreMenu", "insertMenu"]
    menus.forEach(name => {
      if (name !== targetName) {
        this[name + "Target"].classList.add("hidden")
      }
    })
  }

  clearInputs(ids) {
    ids.forEach(id => {
      const el = document.getElementById(id)
      if (el) el.value = ""
    })
  }

  updateToolbarState() {
    // Optional: Add visual active states here later
  }
}
