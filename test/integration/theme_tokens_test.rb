require "test_helper"

# Guard for the dark-mode token mechanism in app/assets/tailwind/application.css.
#
# Dark mode here is not a set of `dark:` variants — it is a redefinition of token
# VALUES under a selector on <html>, which re-colours every existing
# bg-surface-* / text-ink-* utility at once. That is enormously cheaper than the
# alternative, and it has exactly two failure modes, both silent:
#
#   1. A view — or a Stimulus controller building markup in JS — introduces
#      raw colour (bg-white, a Tailwind-palette gray, a hex). Raw colour cannot
#      respond to a token override, so that element stays light forever while
#      everything around it darkens. Nothing errors; the page just develops a
#      white hole. That is what NoRawColourInViewsTest below is for. It scans
#      both app/views and app/javascript: a controller that builds its own
#      innerHTML (board_map_controller.js's error panel, gap_insert_controller.js's
#      composer) is exactly as capable of hardcoding colour as an .erb file, and
#      nothing about "it's JS, not a template" makes it visible to a scan that
#      only reads *.erb.
#
#   2. The two token-mapping blocks drift apart. `[data-theme="dark"]` and the
#      `[data-theme="system"]` copy inside the prefers-color-scheme media query
#      have to stay identical, and CSS gives no way to write the mapping once
#      (see the long comment in the stylesheet). Add a token to one and forget
#      the other and "Dark" works while "Match system" is half-dark.
class ThemeTokensTest < ActiveSupport::TestCase
  CSS_PATH = Rails.root.join("app/assets/tailwind/application.css")

  def css
    @css ||= File.read(CSS_PATH)
  end

  # Pull the declaration list out of a rule, given the selector to look for and
  # which occurrence. Deliberately crude string slicing rather than a CSS parser
  # — the file is hand-written and the shape is stable, and a parser dependency
  # for one guard test is not worth it.
  def declarations_after(selector, from: 0)
    start = css.index(selector, from)
    assert start, "expected to find `#{selector}` in application.css"
    open_brace = css.index("{", start)
    close_brace = css.index("}", open_brace)
    css[(open_brace + 1)...close_brace]
      .scan(/(--[\w-]+)\s*:\s*([^;]+);/)
      .map { |prop, value| [prop, value.strip] }
  end

  test "the dark palette maps the same tokens for explicit dark and for match-system" do
    explicit = declarations_after('[data-theme="dark"] {')

    # The system copy is the one nested inside the media query.
    media_at = css.index("@media (prefers-color-scheme: dark)")
    assert media_at, "the match-system branch must be gated on prefers-color-scheme"
    system = declarations_after('[data-theme="system"] {', from: media_at)

    assert explicit.any?, "the dark token mapping should not be empty"
    assert_equal explicit, system, <<~MSG
      The [data-theme="dark"] and [data-theme="system"] token mappings have
      drifted. They must stay identical — CSS cannot express the mapping once
      (an unconditional selector and a media-query-gated one cannot share a
      rule), so the duplication is intentional and this test is what makes it
      safe.

      Only in [data-theme="dark"]:   #{(explicit - system).map(&:first).join(", ")}
      Only in [data-theme="system"]: #{(system - explicit).map(&:first).join(", ")}
    MSG
  end

  # `color-scheme: dark` is not a `--*` declaration, so the mapping-equality test
  # above steps right over it. It still has to be present in BOTH branches: it is
  # what makes the browser render native checkboxes, the default focus ring and
  # the pre-paint canvas as dark. Missing from the system branch, "Match system"
  # would keep light-styled form controls on a dark page.
  test "both dark branches declare color-scheme: dark" do
    explicit_at = css.index('[data-theme="dark"] {')
    explicit_end = css.index("}", explicit_at)
    assert_includes css[explicit_at...explicit_end], "color-scheme: dark",
                    "[data-theme=dark] must declare color-scheme: dark"

    media_at = css.index("@media (prefers-color-scheme: dark)")
    system_at = css.index('[data-theme="system"] {', media_at)
    system_end = css.index("}", system_at)
    assert_includes css[system_at...system_end], "color-scheme: dark",
                    "the match-system branch must declare color-scheme: dark too"
  end

  test "light mode never declares color-scheme, so nothing changes there" do
    # Only the two dark branches may set it. If it leaked to :root, light mode
    # would start rendering dark native controls.
    assert_equal 2, css.scan(/^\s*color-scheme:/).length,
                 "color-scheme should be declared exactly twice — once per dark branch"
  end

  test "every dark value is defined once and referenced, never inlined twice" do
    mapping = declarations_after('[data-theme="dark"] {')
    referenced = mapping.filter_map { |_, value| value[/var\((--dark-[\w-]+)\)/, 1] }

    assert referenced.any?, "the mapping should point at the shared --dark-* set"

    referenced.each do |name|
      assert_match(/#{Regexp.escape(name)}:\s*#[0-9A-Fa-f]{3,8};/, css,
                   "#{name} is referenced by the dark mapping but never defined")
    end
  end

  test "the theme tokens are declared in a plain @theme block, not @theme inline" do
    # This is the single most load-bearing fact about the mechanism. `@theme
    # inline` makes Tailwind inline each token's VALUE into the utility instead
    # of emitting `var(--color-…)`, which would leave every utility frozen at
    # its light value no matter what the dark blocks say — a dark mode that
    # silently does nothing. Verified here against the source, and against the
    # compiled output in the test below.
    # Both anchored to the start of a line, so the prose in this file's own
    # comments — which necessarily names `@theme inline` to explain why it is
    # wrong — cannot trip the assertion.
    assert_match(/^@theme \{/, css,
                 "tokens must live in a plain `@theme {` block — the inline variant " \
                 "would inline values and break every dark-mode override")
    refute_match(/^@theme\s+inline/, css,
                 "the inline variant of @theme inlines each token's value into the " \
                 "utility instead of emitting var(--color-…), which would leave every " \
                 "utility frozen at its light value and dark mode doing nothing at all")
  end

  test "compiled utilities reference the token variable so an override can reach them" do
    build = Rails.root.join("app/assets/builds/tailwind.css")
    skip "run bin/rails tailwindcss:build first" unless build.exist?

    compiled = File.read(build)

    # A representative utility from each ramp that dark mode redefines. If any of
    # these compiles to a literal, the override silently stops working for it.
    {
      "bg-surface-0"   => "--color-surface-0",
      "text-ink-700"   => "--color-ink-700",
      "border-line"    => "--color-line",
      "text-brand-fg"  => "--color-brand-fg",
      "bg-surface-200" => "--color-surface-200",
      # A ring compiles through --tw-ring-color rather than a plain property,
      # so it is its own code path — and it is the one that replaced a baked
      # `ring-ink-900/5`, which is exactly the failure being guarded against.
      "ring-hairline"  => "--color-hairline"
    }.each do |utility, token|
      rule = compiled[/\.#{Regexp.escape(utility)}\{[^}]*\}/]
      assert rule, "#{utility} is not in the compiled CSS — is it used anywhere?"
      assert_includes rule, "var(#{token})",
                      "#{utility} compiled to a literal instead of var(#{token}); " \
                      "dark mode cannot override it"
    end
  end

  test "scrim and nav chrome stay dark in dark mode rather than inverting" do
    mapping = declarations_after('[data-theme="dark"] {').to_h

    # nav-bg / nav-fg exist precisely so the nav does NOT invert. If a future
    # change adds them to the dark mapping, the top and bottom nav bars turn
    # light in dark mode.
    assert_nil mapping["--color-nav-bg"],
               "nav-bg must not be remapped in dark mode — the nav is dark chrome in BOTH themes"
    assert_nil mapping["--color-nav-fg"],
               "nav-fg must not be remapped in dark mode — it is light text on dark chrome in BOTH themes"

    # nav-fg-muted exists BECAUSE the thing it replaced (text-ink-300 on the
    # notification and help buttons) did invert, dropping those icons from
    # 6.88:1 to 3.82:1 on a nav that had not moved. Remapping it here would
    # reintroduce precisely that.
    assert_nil mapping["--color-nav-fg-muted"],
               "nav-fg-muted must not be remapped — it is the muted foreground on always-dark " \
               "nav chrome, and it was split off ink-300 specifically to stop it inverting"

    # Scrim is not remapped either, and this one is worth pinning because it
    # looks like an oversight. 9 of its 11 uses are `bg-scrim/NN`, and Tailwind
    # bakes an opacity modifier into a literal at build time — so a dark value
    # would reach only `ring-scrim` and the sign-in gradient's `from-scrim`,
    # leaving every actual backdrop on the light value. Half a themed token is
    # worse than none: scrim means the same dark colour in both themes.
    assert_nil mapping["--color-scrim"],
               "scrim must not be remapped — bg-scrim/NN bakes its alpha at build time, " \
               "so the override would reach only the 2 unmodified uses and skip all 9 backdrops"
  end

  # The corollary, asserted directly against the compiled output so it cannot
  # rot: shadows are NOT themeable through --shadow-*, and the espresso value
  # stays in both themes. If Tailwind ever changes this, this test fails and the
  # long comment in the stylesheet needs revisiting.
  test "shadow utilities bake their value, so --shadow-* is not themeable" do
    build = Rails.root.join("app/assets/builds/tailwind.css")
    skip "run bin/rails tailwindcss:build first" unless build.exist?

    rule = File.read(build)[/\.shadow-2xl\{[^}]*\}/]
    assert rule, "shadow-2xl should be in the compiled CSS"

    refute_includes rule, "var(--shadow-2xl)",
                    "if shadow utilities started referencing var(--shadow-2xl), shadows " \
                    "WOULD become themeable and the stylesheet's note saying otherwise is stale"
    assert_includes rule, "2a211c",
                    "the espresso shadow tint should still be baked in"
  end

  test "fill tokens are NOT lightened, so white text on them keeps passing AA" do
    mapping = declarations_after('[data-theme="dark"] {').to_h

    # brand-600/700, danger-600 and success-600 are fills that `text-white` sits
    # on. White text needs its fill at luminance <= 0.1833 to clear 4.5:1, while
    # a foreground on the darkest dark surface needs >= 0.2037 — the ranges do
    # not overlap, which is why the -fg tokens exist. Lightening a FILL here
    # would fix nothing and would quietly break every white button label.
    %w[--color-brand-600 --color-brand-700 --color-danger-600 --color-success-600].each do |fill|
      assert_nil mapping[fill],
                 "#{fill} is a fill with white text on it — lightening it in dark mode " \
                 "breaks that label's contrast. Lighten the matching *-fg token instead."
    end

    # And the foregrounds ARE lightened.
    %w[--color-brand-fg --color-danger-fg --color-success-fg --color-warn-700].each do |fg|
      assert mapping[fg], "#{fg} must be lightened in dark mode to stay legible on a dark surface"
    end
  end
end

# The guard that stops dark mode rotting.
#
# Same shape and intent as ZIndexLayersTest and DropdownAriaTest: the failure it
# prevents is invisible to ordinary assertions. A new panel written with
# `bg-white` renders perfectly, passes its own tests, and is a white rectangle in
# the middle of a dark page — and nobody notices until someone using dark mode
# reports it.
#
# 92 opaque `bg-white` sites existed when dark mode was built. The pre-existing
# "no raw grays" convention had not caught a single one, because white is not a
# gray. That is the whole argument for enforcing this mechanically.
#
# Scans app/views AND app/javascript, for the same reason
# NoBakedAlphaOnThemedTokensTest below does: a Stimulus controller that builds
# markup with `innerHTML` is not a template, but it produces exactly the same
# DOM as one, and a scan that stops at *.erb is blind to it. Two real instances
# existed at the time this scope was added — board_map_controller.js's error
# panel (`bg-white`, plus a `border-danger-600/25` caught by
# NoBakedAlphaOnThemedTokensTest below) and gap_insert_controller.js's
# card-insert composer (`bg-white`) — found by running the extended scan, not
# hypothesised. The map panel's `text-danger-600` was fixed to `text-danger-fg`
# alongside it — not something either guard flags (a bare fill token with no
# alpha modifier isn't raw colour), but the same category of mistake: a FILL
# used as a foreground, staying visually fixed while a REMAPPED surface
# darkens around it.
class NoRawColourInViewsTest < ActiveSupport::TestCase
  # Opaque white/black FILLS.
  #
  # `(?![\w/-])` is the entire subtlety, and getting it wrong in either
  # direction makes this test useless: `bg-white/10` must stay ALLOWED —
  # translucent white over the dark navs and over board wallpaper is correct in
  # both themes and is how every nav hover state is built. Only the OPAQUE fill
  # is unthemeable. Likewise the leading `(?:[a-z-]+:)*` has to be OPTIONAL, or
  # bare `bg-white` — the exact 92-site mistake this exists to catch — walks
  # straight through while only `hover:bg-white` gets flagged.
  OPAQUE_WHITE_BLACK =
    %r{(?:^|[\s"'])(?:[a-z-]+:)*bg-(?:white|black)(?![\w/-])}

  # Black as a FOREGROUND. Nothing uses it today; it is banned pre-emptively
  # because it is exactly as unthemeable as an opaque white fill, and "text-black
  # looked fine when I wrote it" is how the first hole appears. Note `text-white`
  # is deliberately NOT here — white text on a brand/danger fill is correct in
  # both themes and there are 61 legitimate uses of it.
  RAW_BLACK =
    %r{(?:^|[\s"'])(?:[a-z-]+:)*(?:text|border|ring|divide|fill|stroke)-black(?![\w/-])}

  # Any Tailwind stock neutral ramp. The design system has ink-* / surface-* /
  # line for all of these, and a stock gray is both off-palette (they are cool,
  # this theme is warm) and immune to the dark override.
  PALETTE_GRAY =
    %r{(?:^|[\s"'])(?:[a-z-]+:)*(?:bg|text|border|ring|divide|from|via|to|fill|stroke|placeholder|decoration|outline|accent|caret|shadow)-(?:gray|slate|zinc|neutral|stone)-\d+(?![\w-])}

  # Hardcoded hex, including inside an arbitrary value like `text-[#BE451A]`.
  # The `(?<![\w&])` lookbehind keeps HTML entities (`&#39;`) out of it; ERB
  # interpolation (`#{...}`) cannot match because `{` is not a hex digit. JS
  # template interpolation (`${...}`) can't match for an even simpler reason —
  # it starts with `$`, not `#`, so the leading character never lines up.
  HARDCODED_HEX =
    /(?<![\w&])#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})(?![0-9a-fA-F\w])/

  CHECKS = {
    "opaque bg-white / bg-black (use bg-surface-0 — note bg-white/10 IS fine)" => OPAQUE_WHITE_BLACK,
    "black as a foreground (use ink-*)"                                        => RAW_BLACK,
    "Tailwind palette gray (use ink-* / surface-* / line)"                     => PALETTE_GRAY,
    "hardcoded hex (add a token instead)"                                      => HARDCODED_HEX
  }.freeze

  # Scanned together: a colour-class string looks identical whether it sits in
  # an .erb `class="..."` attribute or a JS template literal building innerHTML
  # — same CHECKS, same offender format, so one glob covering both is simpler
  # than two near-duplicate tests.
  SCAN_GLOBS = %w[app/views/**/*.erb app/javascript/**/*.js].freeze

  # Genuine exceptions. Every *.erb site was converted when dark mode landed,
  # so this stayed empty until app/javascript joined the scan turned up one
  # real one that isn't fixable: board_map_controller.js's Mapbox
  # `new mapboxgl.Marker({ color: "#BE451A" })` — Mapbox GL JS takes a CSS
  # colour string for the marker SVG it draws internally, not an element you
  # can hand a class or a CSS var(); it cannot read a custom property, so a
  # literal hex is the only interface it exposes. It is already commented
  # in-place as "must be kept in sync by hand with --color-brand-600". If you
  # add another entry, say which token could not express it and why. "It was
  # quicker" is not a reason; a white panel that cannot darken is a dark-mode
  # bug waiting to be filed.
  ALLOWLIST = %w[app/javascript/controllers/board_map_controller.js].freeze

  test "no view or controller uses raw colour that a theme override cannot reach" do
    offenders = []

    SCAN_GLOBS.flat_map { |g| Dir.glob(Rails.root.join(g)) }.sort.each do |path|
      rel = path.sub("#{Rails.root}/", "")
      next if ALLOWLIST.include?(rel)

      File.readlines(path).each_with_index do |line, i|
        CHECKS.each do |label, pattern|
          next unless line.match?(pattern)

          offenders << "#{rel}:#{i + 1}  [#{label}]  #{line.strip[0, 100]}"
        end
      end
    end

    assert_empty offenders, <<~MSG
      Raw colour found in app/views or app/javascript. Dark mode works by
      redefining token values under a selector on <html>, so a literal colour
      is simply immune to it — the element stays light while the page around
      it goes dark. A Stimulus controller building innerHTML is just as capable
      of this as an .erb template.

      Use the tokens: surface-* (fills), ink-* (text), line (borders),
      brand-fg / danger-fg / success-fg (coloured foregrounds),
      brand-600 / danger-600 / success-600 (fills with white text on them),
      scrim (always-dark overlays), nav-bg / nav-fg (always-dark chrome).

      #{offenders.join("\n  ")}
    MSG
  end

  # Proving the guard actually detects, in the style this codebase expects of a
  # regression test — a guard that cannot fail is decoration. Each of these is
  # the real-world mistake the pattern exists to catch.
  test "the patterns detect the mistakes they are meant to catch" do
    should_flag = [
      %{<div class="bg-white rounded-lg">},                          # THE 92-site mistake
      %{<div class="p-4 bg-white">},                                 # not at start of attr
      %{<div class='bg-white'>},                                     # single-quoted
      %{<div class="focus:bg-white">},                               # prefixed variant
      %{<div class="group-hover:bg-white">},                         # compound prefix
      %{<div class="bg-black">},
      %{<div class="text-black">},
      %{<span class="text-gray-200">},                               # the two nav holdouts
      %{<div class="border-slate-300 bg-zinc-50">},
      %{<div class="text-neutral-500 hover:bg-stone-100">},
      %{<div style="background: #ffffff">},                          # hex in a style attr
      %{<i class="text-[#BE451A]">},                                 # hex in an arbitrary value
      "      <div class=\"h-full flex items-center justify-center bg-white\">"  # JS template-literal innerHTML
    ]

    should_flag.each do |snippet|
      hits = CHECKS.select { |_, pattern| snippet.match?(pattern) }.keys
      assert hits.any?, "guard FAILED TO FLAG: #{snippet}"
    end

    # The other half of a guard that actually guards: it must not fire on what is
    # legitimately there. A noisy guard earns ALLOWLIST entries, and an
    # allowlisted guard protects nothing.
    should_pass = [
      %{<div class="bg-surface-0 text-ink-700 border-line">},        # the correct form
      %{<header class="bg-nav-bg text-nav-fg">},                     # always-dark chrome
      %{<div class="bg-scrim/60">},                                  # modal backdrop
      %{<a class="hover:bg-white/10 ring-white/10">},                # TRANSLUCENT white — allowed
      %{<div class="bg-white/20 hover:bg-white/30 backdrop-blur-sm">},
      %{<button class="bg-brand-600 text-white">},                   # white TEXT on a fill — allowed
      %{<input class="placeholder-white focus:ring-white">},         # nav search on dark chrome
      %{<div class="ring-1 ring-white/10 border-white/20">},
      %{<span class="text-brand-fg hover:text-brand-fg-hover">},
      %{<div class="bg-gradient-to-br from-scrim via-brand-700">},
      %{<%= link_to "x", y, class: "hover:text-white underline" %>},
      %{<div class="shadow-sm bg-surface-muted">}
    ]

    should_pass.each do |snippet|
      flagged = CHECKS.select { |_, pattern| snippet.match?(pattern) }.keys
      assert_empty flagged, "guard WRONGLY FLAGGED legitimate markup: #{snippet} (#{flagged.join(', ')})"
    end
  end

  # Known limitation, asserted rather than left as folklore: the scan is
  # line-based and does not parse ERB or JS, so a COMMENT naming a banned class
  # would be reported as an offender — in either language. Nothing in
  # app/views or app/javascript does that today. Recorded here so the next
  # person who hits it recognises it immediately instead of hunting for markup
  # that isn't there — the fix is to break the class name up in the prose, not
  # to add an ALLOWLIST entry for the whole file. NoBakedAlphaOnThemedTokensTest
  # below shares the same limitation.
  test "the scan is line-based and does not understand ERB or JS comments" do
    assert_match OPAQUE_WHITE_BLACK, %{<%# a comment that says bg-white %>},
                 "if this ever stops being true the limitation note above is stale"
    assert_match OPAQUE_WHITE_BLACK, %{// a JS comment that says bg-white for illustration},
                 "the same line-based limitation applies to JS comments now that app/javascript is in scope"
  end
end

# The third way dark mode rots, after raw colour and mapping drift.
#
# Tailwind v4 resolves an opacity modifier AT BUILD TIME into a literal:
# `ring-ink-900/5` compiles to `--tw-ring-color:#2a211c0d`, with no var() left
# in it. Every other colour utility keeps `var(--color-…)` and flips for free
# when the variable is redefined — these cannot. They are frozen at their light
# value in every theme, and they look completely correct in the source.
#
# That is only a BUG when the token in question is one dark mode actually
# redefines. The distinction is the whole rule:
#
#   PINNED tokens  — scrim, and the -600 fills — mean the same colour in both
#                    themes, so freezing them changes nothing. `bg-scrim/60` is
#                    a backdrop that SHOULD stay dark; `bg-success-600/90` is a
#                    hover step on a fill. Both are fine and both stay.
#
#   REMAPPED tokens — ink-*, surface-*, line, the -fg set, the tints — do flip,
#                    and an alpha on one silently opts that site out of dark
#                    mode. `ring-ink-900/5` measured 1.0:1 against the dark card
#                    it sat on: eight dropdown edges that simply did not exist.
#
# The banned list is READ OUT OF THE STYLESHEET rather than restated here, so
# adding a token to the dark mapping automatically extends this guard and there
# is no second list to keep in sync. There is deliberately no allowlist: at the
# time of writing every remaining alpha-on-token use in app/views and
# app/javascript is on a pinned token, so the rule holds with no exceptions to
# explain.
#
# Scans app/javascript alongside app/views for the same reason
# NoRawColourInViewsTest above does — a controller's template-literal innerHTML
# is not exempt just because it isn't a *.erb file. Extending the scan did NOT
# turn up a new instance of THIS specific bug (an alpha directly on a remapped
# token) in JS; it's mentioned here mainly so the rule's scope doesn't quietly
# drift back to *.erb-only the next time someone edits this file.
#
# What extending the scan's PATHS does not do: widen the RULE. The rule is
# "alpha directly on a token dark mode remaps." board_map_controller.js's
# `border-danger-600/25` was a real bug of a DIFFERENT, narrower shape this
# guard does not model — an alpha on a PINNED fill (danger-600, never remapped)
# composited against a REMAPPED surface underneath it (danger-50/surface-0).
# That was fixed by hand to `border-danger-line`, matching the ERB precedent,
# but nothing here would catch a new `border-danger-600/25` written tomorrow,
# in either app/views or app/javascript — pinned-fill-on-remapped-surface is a
# real remaining hole, not a false sense of coverage from this commit.
class NoBakedAlphaOnThemedTokensTest < ActiveSupport::TestCase
  CSS_PATH = Rails.root.join("app/assets/tailwind/application.css")

  # Every --color-* the dark mapping redefines, i.e. exactly the tokens whose
  # value is theme-dependent and therefore cannot survive being baked.
  def remapped_tokens
    css = File.read(CSS_PATH)
    start = css.index('[data-theme="dark"] {')
    raise "could not find the dark mapping block" unless start

    body = css[(css.index("{", start) + 1)...css.index("}", start)]
    body.scan(/(--color-[\w-]+)\s*:/).flatten.map { |t| t.delete_prefix("--color-") }
  end

  COLOUR_UTILITY =
    /(?:bg|text|ring|border|divide|outline|from|via|to|fill|stroke|placeholder|decoration|accent|caret|shadow)/

  def offence_pattern(tokens)
    # Longest first so `danger-line-strong` is tried before `danger-line`.
    names = Regexp.union(tokens.sort_by { |t| -t.length })
    /(?:^|[\s"'])(?:[a-z-]+:)*#{COLOUR_UTILITY}-#{names}\/\d+/
  end

  SCAN_GLOBS = %w[app/views/**/*.erb app/javascript/**/*.js].freeze

  test "no view or controller bakes an opacity modifier into a token that dark mode remaps" do
    tokens = remapped_tokens
    assert tokens.any?, "expected to read the dark mapping out of application.css"

    pattern = offence_pattern(tokens)
    offenders = []

    SCAN_GLOBS.flat_map { |g| Dir.glob(Rails.root.join(g)) }.sort.each do |path|
      rel = path.sub("#{Rails.root}/", "")
      File.readlines(path).each_with_index do |line, i|
        offenders << "#{rel}:#{i + 1}  #{line.strip[0, 110]}" if line.match?(pattern)
      end
    end

    assert_empty offenders, <<~MSG
      An opacity modifier is applied to a token that dark mode redefines.

      Tailwind bakes `token/NN` into a literal at build time, so that site is
      frozen at its LIGHT value and cannot respond to the dark override — the
      exact failure that left the dropdown hairlines at 1.0:1 and the error-box
      borders at 1.2:1 on dark surfaces.

      Promote it to a real token pair instead: give it a light value equal to
      today's composite (so light mode does not move) and a dark value measured
      against the surface it actually sits on. See --color-hairline /
      --color-danger-line in application.css for the shape.

      An alpha on a PINNED token (scrim, brand-600/danger-600/success-600) is
      fine and is not flagged — those mean the same colour in both themes.

      #{offenders.join("\n  ")}
    MSG
  end

  # A guard that cannot fail is decoration — prove both directions.
  test "the guard flags remapped tokens and leaves pinned ones alone" do
    pattern = offence_pattern(remapped_tokens)

    should_flag = [
      %{<div class="ring-1 ring-ink-900/5">},              # the 8 dropdown hairlines
      %{<div class="border border-danger-600/25">}.sub("danger-600", "danger-line"),
      %{<div class="bg-surface-0/50">},
      %{<div class="hover:border-line/40">},               # prefixed variant
      %{<span class='text-ink-500/70'>},                   # single-quoted
      '      <div class="rounded-lg ring-1 ring-ink-900/5">'  # JS template-literal innerHTML
    ]
    should_flag.each do |snippet|
      assert_match pattern, snippet, "guard FAILED TO FLAG: #{snippet}"
    end

    should_pass = [
      %{<div class="bg-scrim/60">},                        # always-dark backdrop
      %{<div class="bg-scrim/30 hover:bg-scrim/50">},
      %{<button class="bg-danger-600 hover:bg-danger-600/90 text-white">},  # fill hover step
      %{<div class="bg-success-600/90 text-white">},
      %{<a class="hover:bg-white/10 ring-white/10">},      # translucent white — out of scope
      %{<div class="ring-1 ring-hairline border border-danger-line">}       # the promoted form
    ]
    should_pass.each do |snippet|
      refute_match pattern, snippet, "guard WRONGLY FLAGGED: #{snippet}"
    end
  end

  # The promoted tokens must actually BE in the dark mapping — a light-only
  # token would look promoted and behave exactly like the baked literal it
  # replaced, which is the failure mode this whole commit exists to remove.
  test "the promoted boundary tokens are themed, not merely renamed" do
    tokens = remapped_tokens

    %w[hairline danger-line danger-line-strong].each do |name|
      assert_includes tokens, name,
                      "--color-#{name} replaced a baked opacity modifier, so it MUST be " \
                      "remapped in dark mode — otherwise it is the same frozen literal " \
                      "under a nicer name"
    end
  end
end
