require "test_helper"

# Guard for a convention that has had no test until now: inline JS handlers
# were swept out of the views months ago, but unlike raw colour, baked alpha,
# frame targets, notification coverage, dropdown ARIA and the z-index ladder
# — all of which are guarded elsewhere — nothing stopped it from creeping
# back in. An inline handler is invisible to every other guard here (it's
# neither a colour nor a frame target) and Content-Security-Policy-hostile
# besides, so it deserves the same mechanical enforcement.
#
# Two distinct shapes get banned, because a sweep that only catches one of
# them just relocates the mistake to the other:
#
#   1. A literal HTML attribute:      <button onclick="doStuff()">
#   2. A Rails helper hash option:    link_to "x", y, onclick: "doStuff()"
#
# Both hand a string of JS to the browser outside of app/javascript, where it
# can't be linted, can't be Stimulus-tested, and (for the attribute form)
# can't be allowed by a CSP that omits 'unsafe-inline'.
class NoInlineJavascriptTest < ActiveSupport::TestCase
  # The standard HTML/DOM GlobalEventHandlers content attributes, enumerated
  # by name rather than matched with a generic /on[a-z]+/ pattern. A generic
  # pattern false-positives on ordinary Ruby/English words that happen to
  # start with "on" — `only:` (lists/_header.html.erb, _top_nav.html.erb,
  # _sidebar.html.erb) and `once: true` (lists/edit.html.erb,
  # cards/show.html.erb) both appear legitimately in this app's views today,
  # and both would match `on[a-z]+:`. A closed, real list of event names
  # cannot match either.
  EVENT_HANDLERS = %w[
    onabort onanimationend onanimationiteration onanimationstart
    onbeforeunload onblur oncancel oncanplay oncanplaythrough onchange
    onclick onclose oncontextmenu oncopy oncuechange oncut ondblclick
    ondrag ondragend ondragenter ondragleave ondragover ondragstart ondrop
    ondurationchange onemptied onended onerror onfocus onhashchange
    oninput oninvalid onkeydown onkeypress onkeyup onload onloadeddata
    onloadedmetadata onloadstart onmessage onmousedown onmouseenter
    onmouseleave onmousemove onmouseout onmouseover onmouseup onmousewheel
    onoffline ononline onpagehide onpageshow onpaste onpause onplay
    onplaying onpointercancel onpointerdown onpointerenter onpointerleave
    onpointermove onpointerout onpointerover onpointerup onpopstate
    onprogress onratechange onreset onresize onscroll onseeked onseeking
    onselect onselectstart onshow onstalled onstorage onsubmit onsuspend
    ontimeupdate ontoggle ontouchcancel ontouchend ontouchmove ontouchstart
    ontransitionend onunload onvolumechange onwaiting onwheel
  ].freeze

  # Longest first so `ontouchstart` is tried before a hypothetical shorter
  # prefix could steal the match.
  EVENT_NAMES = Regexp.union(EVENT_HANDLERS.sort_by { |n| -n.length })

  # Form 1: a literal HTML attribute — `onclick="..."` or `onclick='...'`.
  # The `(?<![\w-])` lookbehind keeps this from matching in the middle of a
  # longer token (a hypothetical `data-onclick` custom attribute, say).
  ATTRIBUTE_FORM = /(?<![\w-])#{EVENT_NAMES}\s*=\s*["']/i

  # Form 2: a Rails/Ruby hash-option key — `onclick: "..."` — as passed to
  # link_to, content_tag, tag.button, button_to, and friends.
  HASH_OPTION_FORM = /(?<![\w-])#{EVENT_NAMES}:/i

  CHECKS = {
    "inline HTML event-handler attribute (move it to a Stimulus action)" => ATTRIBUTE_FORM,
    "inline event-handler passed as a helper hash option (use data-action)" => HASH_OPTION_FORM
  }.freeze

  # Views only — app/javascript is where JS is SUPPOSED to live; the
  # convention this guards is that none of it leaks into app/views.
  SCAN_GLOBS = %w[app/views/**/*.erb].freeze

  # root defaults to Rails.root so the real guard scans the live app/views;
  # the canary test below passes an isolated tmp dir instead. Writing the
  # canary directly into app/views was tried first and was flaky: this suite
  # runs parallelized (test_helper.rb), so a canary file sitting in the real
  # app/views — even briefly, even inside a begin/ensure — could be caught
  # mid-flight by this test's own main scan running in a different worker
  # process at the same time. Scanning an isolated root removes the shared
  # mutable state instead of trying to sequence around it.
  def scan(root = Rails.root)
    offenders = []

    SCAN_GLOBS.flat_map { |g| Dir.glob(root.join(g)) }.sort.each do |path|
      rel = path.sub("#{root}/", "")

      File.readlines(path).each_with_index do |line, i|
        CHECKS.each do |label, pattern|
          next unless line.match?(pattern)

          offenders << "#{rel}:#{i + 1}  [#{label}]  #{line.strip[0, 100]}"
        end
      end
    end

    offenders
  end

  test "no view uses an inline JavaScript event handler, in either form" do
    offenders = scan

    assert_empty offenders, <<~MSG
      Inline JavaScript handler found in app/views. Stimulus is this app's
      answer to "run some JS when something happens" — wire it through
      data-controller / data-action instead:

        <button data-action="click->my-controller#doStuff">

      Allowed and NOT flagged by this guard: external <script src="...">
      tags (Mapbox), <script type="application/json"> data islands (the
      board map's marker data), and the mailer layout's <style> block —
      none of those are inline event handlers.

      #{offenders.join("\n  ")}
    MSG
  end

  # A guard that cannot fail is decoration — prove both banned forms are
  # actually caught, and that the real exceptions are not.
  test "the patterns detect both banned forms and leave the real exceptions alone" do
    should_flag = [
      %{<button onclick="doStuff()">Click</button>},                    # the classic case
      %{<div onblur='hide()'>},                                         # single-quoted
      %{<input onchange="update(this)" type="text">},                   # mid-attribute-list
      %{<%= link_to "Delete", path, onclick: "return confirm('sure?')" %>},   # hash option, ERB
      %{<%= content_tag :div, "hi", onclick: "foo()" %>},               # hash option, another helper
      %{  data: { onclick: "trackEvent()" } }                           # hash option, nested
    ]
    should_flag.each do |snippet|
      hits = CHECKS.select { |_, pattern| snippet.match?(pattern) }.keys
      assert hits.any?, "guard FAILED TO FLAG: #{snippet}"
    end

    should_pass = [
      %{<script src="https://api.mapbox.com/mapbox-gl.js"></script>},                  # external script
      %{<script type="application/json" data-board-map-target="data">{"markers":[]}</script>}, # JSON island
      %{    <style>},                                                    # mailer layout's <style> block
      %{      body { background: #f4f4f4; color: #222; }},               # CSS inside that block
      %{<%= link_to "Boards", boards_path, class: "only:hover:underline" %>},  # "only" — not an event name
      %{<%= form_with once: true do |f| %>},                             # "once" — not an event name
      %{<div data-controller="board-filter" data-action="click->board-filter#toggle">} # real Stimulus wiring
    ]
    should_pass.each do |snippet|
      flagged = CHECKS.select { |_, pattern| snippet.match?(pattern) }.keys
      assert_empty flagged, "guard WRONGLY FLAGGED legitimate markup: #{snippet} (#{flagged.join(', ')})"
    end
  end

  # The strongest proof: inject one real violation of each banned form into
  # an actual file — under an isolated tmp directory, not the live app/views
  # (see the comment on `scan` for why) — run the SAME scan the guard test
  # above runs, and confirm it is reported with its file and line number, then
  # let Dir.mktmpdir clean up. This is the "confirm each fails with file and
  # line, revert" requested for this guard specifically, over and above the
  # regex-only proof above.
  test "the guard flags a real injected violation with file and line, in both forms" do
    Dir.mktmpdir do |tmp_root|
      root = Pathname.new(tmp_root)
      canary_dir = root.join("app/views")
      FileUtils.mkdir_p(canary_dir)
      canary_path = canary_dir.join("canary.html.erb")

      File.write(canary_path, <<~ERB)
        <div>before</div>
        <button onclick="doStuff()">Click</button>
        <%= link_to "x", "/y", onclick: "doStuff()" %>
      ERB

      offenders = scan(root)

      attribute_hit = offenders.find { |o| o.start_with?("app/views/canary.html.erb:2") }
      hash_hit = offenders.find { |o| o.start_with?("app/views/canary.html.erb:3") }

      assert attribute_hit, "expected the onclick=\"...\" attribute on line 2 to be flagged with its line number"
      assert hash_hit, "expected the onclick: \"...\" hash option on line 3 to be flagged with its line number"
    end
  end

  # Known limitation, matching NoRawColourInViewsTest's own note: the scan is
  # line-based and does not parse ERB, so a comment merely naming a banned
  # pattern would be reported as an offender.
  test "the scan is line-based and does not understand ERB comments" do
    assert_match ATTRIBUTE_FORM, %{<%# an example: onclick="doStuff()" %>},
                 "if this ever stops being true the limitation note above is stale"
  end
end
