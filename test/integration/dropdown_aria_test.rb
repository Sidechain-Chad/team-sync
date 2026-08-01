require "test_helper"

# Guard for the dropdown trigger contract (sweep finding D4).
#
# dropdown_controller.js keeps aria-expanded in sync on every path that opens
# or closes a menu (toggle / open / close / hide / escape / closeOtherDropdowns),
# but it can only do that for a dropdown that actually declares a `trigger`
# target. A new dropdown pasted from an existing one without that target is
# silently non-announcing: the menu opens, nothing tells assistive tech, and no
# request-body assertion anywhere would notice. Hence a structural guard.
#
# The contract, for every `data-controller="… dropdown …"` element:
#
#   1. exactly one `data-dropdown-target="trigger"` in the same file,
#   2. that trigger carries BOTH aria-haspopup and aria-expanded,
#   3. no role="menu" (or its menuitem family) anywhere in app/views.
#
# On (3): several of these popovers contain real forms — the WIP-limit number
# field, the copy-list name field, the move-card selects, the checklist title.
# role="menu" requires menuitem children and owns arrow-key navigation; a text
# input inside one is invalid and leaves a screen-reader user worse off than no
# role at all. So the trigger gets aria-haspopup/aria-expanded and the panel
# stays a plain container. Arrow-key roving focus is deliberately out of scope
# for the same reason.
class DropdownAriaTest < ActiveSupport::TestCase
  VIEWS = Rails.root.join("app/views")

  # `dropdown` as a whole word inside a data-controller list — several of these
  # elements stack controllers ("dropdown search", "dropdown move-picker",
  # "dropdown card-actions-menu"), so a substring match isn't enough.
  DROPDOWN_CONTROLLER = /data-controller="[^"]*\bdropdown\b[^"]*"/
  TRIGGER_TARGET      = 'data-dropdown-target="trigger"'

  # menuitem/menuitemcheckbox/menuitemradio are banned alongside menu/menubar:
  # a menuitem outside a menu container is just as invalid as the container
  # would be here, so allowing one half of the pair only invites the other.
  MENU_ROLE = /role="(menu|menubar|menuitem|menuitemcheckbox|menuitemradio)"/

  def view_files
    Dir.glob(VIEWS.join("**/*.erb")).sort
  end

  test "every dropdown declares exactly one trigger target" do
    # Counted per file rather than per element: a trigger always lives inside
    # its own controller's element, and no partial in this app declares a
    # dropdown whose trigger is rendered from a different file. If that ever
    # changes, this is the assertion to revisit.
    mismatches = view_files.filter_map do |path|
      source    = File.read(path)
      dropdowns = source.scan(DROPDOWN_CONTROLLER).size
      triggers  = source.scan(TRIGGER_TARGET).size
      next if dropdowns == triggers

      "#{path.sub("#{Rails.root}/", "")}: #{dropdowns} dropdown(s), #{triggers} trigger target(s)"
    end

    assert_empty mismatches, <<~MSG
      Every element with data-controller="dropdown" needs one child carrying
      data-dropdown-target="trigger" — without it the controller cannot keep
      aria-expanded in sync, and Esc cannot return focus to the button.

        #{mismatches.join("\n  ")}
    MSG
  end

  test "every dropdown trigger carries aria-haspopup and aria-expanded" do
    offenders = view_files.flat_map do |path|
      source = File.read(path)
      rel    = path.sub("#{Rails.root}/", "")

      each_trigger_tag(source).filter_map do |tag, line|
        missing = []
        missing << "aria-haspopup"  unless tag.include?("aria-haspopup")
        missing << "aria-expanded"  unless tag.include?("aria-expanded")
        next if missing.empty?

        "#{rel}:#{line} missing #{missing.join(' + ')}"
      end
    end

    assert_empty offenders, <<~MSG
      A dropdown trigger must announce both that it opens a popup
      (aria-haspopup="true", the value the two pre-existing ones in
      cards/show.html.erb already use) and whether it is currently open
      (aria-expanded, rendered "false" and then owned by the controller).

        #{offenders.join("\n  ")}
    MSG
  end

  test "no view uses role=menu or a menuitem role" do
    offenders = view_files.flat_map do |path|
      rel = path.sub("#{Rails.root}/", "")
      File.readlines(path).each_with_index.filter_map do |line, i|
        "#{rel}:#{i + 1}" if line.match?(MENU_ROLE)
      end
    end

    assert_empty offenders, <<~MSG
      role="menu" requires menuitem children and arrow-key navigation. These
      popovers contain forms (WIP limit, copy list, move card, add checklist),
      and a text input inside role="menu" is invalid — worse for assistive tech
      than no role at all. Use aria-haspopup/aria-expanded on the trigger only.

        #{offenders.join("\n  ")}
    MSG
  end

  private

  # Yields [full opening tag, 1-based line number] for each trigger target in
  # the source. Attributes are spread over several lines in these views, so a
  # per-line regex would miss them; and ERB inside attribute values
  # (aria-label="Move card, currently in <%= … %>") means the tag boundaries
  # can't be found by naive scanning for "<" and ">" either.
  def each_trigger_tag(source)
    Enumerator.new do |yielder|
      offset = 0
      while (index = source.index(TRIGGER_TARGET, offset))
        start = tag_start(source, index)
        stop  = tag_end(source, start)
        yielder << [source[start..stop], source[0...start].count("\n") + 1]
        offset = index + TRIGGER_TARGET.length
      end
    end
  end

  # Walk back to the "<" that opens this tag, stepping over any "<%" that
  # belongs to an ERB expression sitting earlier in the same tag.
  def tag_start(source, index)
    cursor = index
    while (cursor = source.rindex("<", cursor - 1))
      return cursor unless source[cursor, 2] == "<%"
    end
    0
  end

  # Walk forward from the tag's "<" to the ">" that closes it, ignoring every
  # ">" inside a quoted attribute value. Two kinds of those show up here and
  # both broke a naive scan: Stimulus actions ("click->dropdown#toggle") and
  # ERB in an attribute ("Move card, currently in <%= … %>").
  def tag_end(source, start)
    quote = nil
    (start...source.length).each do |cursor|
      char = source[cursor]
      if quote
        quote = nil if char == quote
      elsif char == '"' || char == "'"
        quote = char
      elsif char == ">"
        return cursor
      end
    end
    source.length - 1
  end
end
