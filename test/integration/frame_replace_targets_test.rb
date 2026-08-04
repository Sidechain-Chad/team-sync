require "test_helper"

# Guard for one bug class, found twice in one afternoon.
#
# THE RULE: a `turbo_stream.replace` (or `broadcast_replace_to`) whose target is
# a TURBO-FRAME must re-emit that frame in its content. `replace` swaps the whole
# target ELEMENT — so replacing a frame with bare markup deletes the frame, and
# the next link or form aimed at it falls back to a full-page visit. In this app
# those fallbacks land on frame-only templates, so the page is destroyed.
#
# Known occurrences, both fixed by switching to `update` (which sets contents and
# leaves the element alone):
#
#   * cards/create.turbo_stream.erb  -> list_<id>_new_card  (add a second card,
#     board vanishes)
#   * labels/create.turbo_stream.erb -> new_label_row       (create a second
#     label, card modal vanishes)
#
# And it is why cards/show.html.erb re-declares turbo_frame_tag "modal" with
# mirrored attributes — the same lesson, learned earlier and written down there.
#
# Static rather than behavioural, matching ZIndexLayersTest and
# NotificationCoverageTest: a response-level test only covers the endpoints
# someone remembered to exercise, and the whole point here is the site nobody
# thought about.
class FrameReplaceTargetsTest < ActiveSupport::TestCase
  VIEWS = Rails.root.join("app/views")

  # Targets whose value isn't a literal, so the scanner can't resolve a shape.
  # Each needs a human to have checked it. Keep the reason.
  DYNAMIC_ALLOWLIST = {
    "app/views/labels/form_errors.turbo_stream.erb" =>
      "frame_id is \"new_label_row\" or \"label_row_<id>\"; both are frames, and the " \
      "block renders cards/_label_form, which re-declares turbo_frame_tag frame_id.",
    "app/controllers/cards_controller.rb" =>
      "update_title picks dom_id(@card, :modal_title)/:tile_title with the matching " \
      "cards/_modal_title or cards/_tile_title partial; both partials declare their frame."
  }.freeze

  # --- shape helpers ---------------------------------------------------------
  # A "shape" normalises an id so "label_row_#{label.id}" and
  # dom_id(label_row, ...) collapse to one comparable token: label_row_*

  SUFFIX_ALIAS = { "item" => "checklist_item", "attachment" => "active_storage_attachment" }

  def self.base_of(token)
    b = token.strip.sub(/\A@/, "").split(".").last.to_s
    b = b.sub(/\A(new_|copied_|target_)/, "")
    SUFFIX_ALIAS[b] || b
  end

  def self.shape(expr)
    e = expr.to_s.strip.sub(/\A\(\s*/, "")
    if (m = e.match(/\A(?:helpers\.)?dom_id\(\s*([^,)]+?)\s*(?:,\s*:?(\w+)\s*)?\)/))
      b = base_of(m[1])
      return m[2] ? "#{m[2]}_#{b}_*" : "#{b}_*"
    end
    if (m = e.match(/\A"([^"]*)"/)) || (m = e.match(/\A'([^']*)'/))
      return m[1].gsub(/#\{[^}]*\}/, "*")
    end
    if (m = e.match(/\A(@?\w+)\s*[,)]/)) || (m = e.match(/\A(@?\w+)\s*$/))
      tok = m[1]
      return nil if %w[frame frame_id partial target].include?(tok)
      return "#{base_of(tok)}_*"
    end
    nil
  end

  # ERB comments are stripped before scanning. Without this, the prose in
  # cards/show.html.erb and cards/create.turbo_stream.erb WARNING people about
  # this exact bug is itself picked up as an offending call site.
  def self.strip_comments(source, path)
    src = source.gsub(/<%#.*?%>/m, "")
    src = src.gsub(/^\s*#.*$/, "") if path.end_with?(".rb")
    src
  end

  # Frames declared anywhere in the view layer, shape => [locations]
  def self.declared_frames
    @declared_frames ||= begin
      found = Hash.new { |h, k| h[k] = [] }
      Dir.glob(VIEWS.join("**/*.erb")).each do |path|
        rel = path.sub("#{Rails.root}/", "")
        strip_comments(File.read(path), path).each_line.with_index do |line, i|
          if (m = line.match(/turbo_frame_tag\s+(.+)$/))
            s = shape(m[1])
            found[s] << "#{rel}:#{i + 1}" if s
          end
          line.scan(/<turbo-frame\s+id="([^"]+)"/) do
            found[$1.gsub(/#\{[^}]*\}/, "*")] << "#{rel}:#{i + 1}"
          end
        end
      end
      found
    end
  end

  # Frame shapes a given file can emit: its own turbo_frame_tags, plus those
  # declared by any partial it renders.
  def self.emitted_shapes(path)
    src = strip_comments(File.read(path), path)
    shapes = src.scan(/turbo_frame_tag\s+(.+)$/).filter_map { |(a)| shape(a) }
    shapes += src.scan(/<turbo-frame\s+id="([^"]+)"/).map { |(id)| id.gsub(/#\{[^}]*\}/, "*") }
    src.scan(/(?:render|template:|partial:)\s*"([a-z0-9_\/]+)"/).each do |(name)|
      shapes += partial_shapes(name)
    end
    shapes.uniq
  end

  def self.partial_shapes(name)
    dir, base = File.split(name)
    [VIEWS.join(dir, "_#{base}.html.erb"), VIEWS.join(dir, "#{base}.html.erb")].each do |candidate|
      next unless File.exist?(candidate)
      src = strip_comments(File.read(candidate), candidate.to_s)
      out = src.scan(/turbo_frame_tag\s+(.+)$/).filter_map { |(a)| shape(a) }
      out += src.scan(/<turbo-frame\s+id="([^"]+)"/).map { |(id)| id.gsub(/#\{[^}]*\}/, "*") }
      return out
    end
    []
  end

  # Every replace/broadcast_replace_to call site in the app.
  def self.replace_sites
    sites = []
    Dir.glob(Rails.root.join("app/**/*.{rb,erb}")).each do |path|
      rel = path.sub("#{Rails.root}/", "")
      lines = strip_comments(File.read(path), path).lines

      lines.each_with_index do |line, i|
        if (m = line.match(/turbo_stream\.replace(?!_all)(.*)$/))
          arg = m[1].to_s
          arg = lines[i + 1].to_s if arg.strip.empty? || arg.strip == "("
          sites << { target: shape(arg), raw: arg.strip[0, 40], file: rel, path: path,
                     line: i + 1, kind: "turbo_stream.replace", context: lines[i, 6].join }
        end
        next unless line.include?("broadcast_replace_to")
        win = lines[i, 8].join
        tgt = win[/target:\s*((?:helpers\.)?dom_id\([^)]*\)|"[^"]*"|[^,\n]+)/, 1]
        sites << { target: shape(tgt), raw: tgt.to_s.strip[0, 40], file: rel, path: path,
                   line: i + 1, kind: "broadcast_replace_to", context: win }
      end
    end
    sites
  end

  # --- the guard -------------------------------------------------------------

  test "every replace whose target is a turbo-frame re-emits that frame" do
    frames = self.class.declared_frames

    offenders = self.class.replace_sites.filter_map do |site|
      next unless site[:target]              # dynamic — covered by the test below
      next unless frames.key?(site[:target]) # plain element — replace is correct

      content = site[:context][/(?:partial|template):\s*"([a-z0-9_\/]+)"/, 1]
      emitted = content ? self.class.partial_shapes(content) : self.class.emitted_shapes(site[:path])

      next if emitted.include?(site[:target])

      "#{site[:file]}:#{site[:line]} — #{site[:kind]} targets <turbo-frame id=\"#{site[:target]}\"> " \
        "(declared at #{frames[site[:target]].first}) but its content never re-emits it" \
        "#{content ? " (content: #{content})" : ""}"
    end

    assert_empty offenders, <<~MSG
      A turbo_stream.replace / broadcast_replace_to is destroying its own frame.

      `replace` swaps the whole target ELEMENT. When the target is a turbo-frame,
      the frame must appear in the replacement content — otherwise the next link
      or form aimed at that frame falls back to a full-page visit, and in this app
      that lands on a frame-only template and wipes the page.

      Two fixes, in order of preference:
        1. Use turbo_stream.update — sets the frame's contents, leaves the frame
           alone. Right when only the contents change (both known cases).
        2. Keep replace and wrap the content in turbo_frame_tag "<the target>",
           mirroring every attribute the original frame had. Needed when the frame
           itself must be re-established (see cards/show.html.erb's "modal").

      #{offenders.join("\n      ")}
    MSG
  end

  # A target the scanner cannot resolve is not automatically fine — it just can't
  # be checked. Requiring an entry means a new dynamic target has to be looked at
  # by a person rather than silently skipped.
  test "every unresolvable replace target has been checked by hand" do
    unresolved = self.class.replace_sites.reject { |s| s[:target] }
                     .reject { |s| DYNAMIC_ALLOWLIST.key?(s[:file]) }
                     .map { |s| "#{s[:file]}:#{s[:line]} — target expression: #{s[:raw]}" }

    assert_empty unresolved, <<~MSG
      Replace sites with a non-literal target that nobody has vetted.

      Work out whether the target is a turbo-frame. If it is, make sure the content
      re-emits it (or switch to `update`), then add the file to DYNAMIC_ALLOWLIST
      in this test with a one-line reason.

      #{unresolved.join("\n      ")}
    MSG
  end

  # Cheap canary: if this ever finds nothing, the scanner has broken and both
  # tests above are passing vacuously.
  test "the scanner actually finds the known frame targets" do
    frames = self.class.declared_frames

    assert_includes frames.keys, "modal"
    assert_includes frames.keys, "list_*_new_card"
    assert_includes frames.keys, "new_label_row"
    assert_includes frames.keys, "card_*"

    frame_targeted = self.class.replace_sites.count { |s| s[:target] && frames.key?(s[:target]) }
    assert_operator frame_targeted, :>=, 15,
      "expected the sweep to still be finding the frame-targeted replace sites; " \
      "found #{frame_targeted}, so the scanner has probably stopped matching"
  end
end
