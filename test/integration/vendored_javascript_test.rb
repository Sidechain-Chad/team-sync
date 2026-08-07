require "test_helper"

# Guard for the one way `bin/importmap pin` can silently hand you a broken
# vendored file.
#
# jspm.io (the provider importmap-rails' packager uses) sometimes splits a
# module's shared code into an internal chunk and re-exports it via a
# RELATIVE import — `export{...}from"../_/Bz2Filul.js"` — resolved against
# the chunk's URL on JSPM'S OWN CDN. `bin/importmap pin` downloads the file
# body verbatim and writes it into vendor/javascript with no rewriting, so
# that relative path now points at OUR origin instead
# (http://localhost:3000/_/Bz2Filul.js), which 404s — the chunk was never
# fetched or vendored, only referenced.
#
# This broke @tiptap/core/jsx-runtime@3.29.2 (a transitive dependency pulled
# in by @tiptap/extension-blockquote and @tiptap/extension-bold, both part of
# @tiptap/starter-kit) the first time tiptap was vendored. It was hand-patched
# — the chunk's ~250 bytes inlined directly into the vendored file, documented
# in place — and VERIFIED working end to end (typing, toolbar formatting,
# saving, zero console errors).
#
# The hand patch is exactly the risk this test exists to catch: `bin/importmap
# pin` has no memory of it. Re-running pin for @tiptap/core (a version bump,
# `bin/importmap update`, or `bin/importmap pristine`) regenerates the file
# from jspm.io and silently reintroduces the broken relative import, with
# nothing in the tool itself to notice. This scans EVERY vendored file for the
# pattern, not just the one known-fixed file, because the same jspm.io chunking
# behaviour could just as easily hit a different package on a future pin.
class VendoredJavascriptTest < ActiveSupport::TestCase
  VENDOR_GLOB = "vendor/javascript/**/*.js"

  # Matches an import/re-export whose source starts with `../` — the shape of
  # a path that was relative to jspm.io's OWN url space and cannot survive
  # being copied verbatim into our vendor directory. A same-directory relative
  # import (`./`) would be fine if it ever occurred, since sibling files in
  # vendor/javascript actually exist; `../` walks OUTSIDE vendor/javascript
  # entirely, which is never valid for a file that lives at its root.
  RELATIVE_PARENT_IMPORT = /\bfrom\s*["']\.\.\//

  test "no vendored package imports from a path outside vendor/javascript" do
    offenders = []

    Dir.glob(Rails.root.join(VENDOR_GLOB)).sort.each do |path|
      rel = path.sub("#{Rails.root}/", "")
      content = File.read(path)

      content.each_line.with_index(1) do |line, i|
        offenders << "#{rel}:#{i}  #{line.strip[0, 120]}" if line.match?(RELATIVE_PARENT_IMPORT)
      end
    end

    assert_empty offenders, <<~MSG
      A vendored file imports from a path outside vendor/javascript. This is
      jspm.io's shared-chunk pattern — `bin/importmap pin` copied the file body
      verbatim without following or rewriting that relative reference, so it
      now points at a path on OUR origin that was never fetched and 404s the
      instant the file is imported (this is exactly how
      @tiptap/core/jsx-runtime broke the first time tiptap was vendored).

      Fix: fetch the missing chunk directly from the URL comment at the top of
      the offending file (swap its own filename for the relative path), inline
      its contents in place of the broken import, and document why — see
      vendor/javascript/@tiptap--core--jsx-runtime.js for the shape.

      #{offenders.join("\n  ")}
    MSG
  end

  # A guard that cannot fail is decoration.
  test "the pattern detects the mistake it exists to catch" do
    assert_match RELATIVE_PARENT_IMPORT,
                 %{export{F as Fragment,h as createElement,h}from"../_/Bz2Filul.js";},
                 "guard FAILED TO FLAG the exact @tiptap/core/jsx-runtime breakage"

    refute_match RELATIVE_PARENT_IMPORT, %{export{F as Fragment,h}from"./local-sibling.js";},
                 "a same-directory relative import is not the bug this guards against"
    refute_match RELATIVE_PARENT_IMPORT, %{import flatpickr from "flatpickr";},
                 "an importmap-resolved bare specifier is not a relative path at all"
  end

  # The known-fixed file specifically, so a future `bin/importmap pin` that
  # regenerates it (undoing the patch) fails LOUDLY here even before the
  # general scan above would also catch it — two independent trip-wires on
  # the one file already proven to break.
  test "tiptap's jsx-runtime patch is still in place" do
    path = Rails.root.join("vendor/javascript/@tiptap--core--jsx-runtime.js")
    skip "file not vendored" unless path.exist?

    content = File.read(path)
    refute_match(RELATIVE_PARENT_IMPORT, content,
                 "@tiptap--core--jsx-runtime.js has reverted to the broken relative chunk " \
                 "import — re-apply the inline patch (see the file's own header comment)")
    assert_match(/export\{F as Fragment/, content,
                 "the patched file should still export Fragment/createElement/jsx/jsxs/jsxDEV")
  end
end
