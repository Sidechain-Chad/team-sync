module PlannerHelper
  # Colour the planner chip by the card's first label, falling back to a
  # neutral gray if the card has no labels. Keeps the calendar visually
  # parseable at a glance — same colour-language as the cards on the board.
  def planner_chip_classes(card)
    "#{planner_chip_fill_classes(card)} border-l-4 #{planner_chip_stripe_class(card)}"
  end

  # Which part of a multi-day bar this cell is: :start, :middle or :end.
  # :point for anything that isn't a real span — no start date, or a start and
  # due on the same calendar day. Points render exactly as they always have.
  def planner_segment(card, day)
    return :point unless card.date_range?

    first_day = card.start_date.to_date
    last_day  = card.due_date.to_date
    return :point if first_day == last_day

    case day
    when first_day then :start
    when last_day  then :end
    else                :middle
    end
  end

  # Bar segments drop the left stripe on continuation cells and square off the
  # inner edges, so consecutive cells read as one continuous bar. Negative
  # margins bleed the fill across the day cell's own padding. :point returns
  # the untouched chip classes — the pre-start_date look, byte for byte.
  def planner_chip_or_bar_classes(card, day)
    fill = planner_chip_fill_classes(card)

    case planner_segment(card, day)
    when :start  then "#{fill} border-l-4 #{planner_chip_stripe_class(card)} rounded-l rounded-r-none -mr-1.5"
    when :middle then "#{fill} rounded-none -mx-1.5"
    when :end    then "#{fill} rounded-l-none rounded-r -ml-1.5"
    else              "#{planner_chip_classes(card)} rounded"
    end
  end

  # The title is only worth repeating where a viewer would otherwise lose it:
  # the day the range starts, and again at the start of each new week row
  # (Sunday) that the bar continues into.
  def planner_segment_shows_title?(card, day)
    planner_segment(card, day) == :point ||
      day == card.start_date.to_date ||
      day.sunday?
  end

  private

  # Background + text colour for a card's chip, without the left stripe.
  # Reuse the label colour helper your existing label_pills view uses.
  # Mapping is the same set of colours your labels can be — Label::COLORS
  # itself is left untouched by the rebrand (user-chosen content colors,
  # not theme chrome), only the "no label" fallback is chrome.
  def planner_chip_fill_classes(card)
    case card.labels.first&.color
    when "red"     then "bg-red-50 text-red-800"
    when "orange"  then "bg-orange-50 text-orange-800"
    when "yellow"  then "bg-yellow-50 text-yellow-800"
    when "green"   then "bg-green-50 text-green-800"
    when "lime"    then "bg-lime-50 text-lime-800"
    when "sky"     then "bg-sky-50 text-sky-800"
    when "blue"    then "bg-blue-50 text-blue-800"
    when "purple"  then "bg-purple-50 text-purple-800"
    when "pink"    then "bg-pink-50 text-pink-800"
    when "black"   then "bg-gray-100 text-gray-900"
    else                "bg-surface-200 text-ink-500"
    end
  end

  def planner_chip_stripe_class(card)
    case card.labels.first&.color
    when "red"     then "border-red-500"
    when "orange"  then "border-orange-500"
    when "yellow"  then "border-yellow-500"
    when "green"   then "border-green-500"
    when "lime"    then "border-lime-500"
    when "sky"     then "border-sky-500"
    when "blue"    then "border-blue-500"
    when "purple"  then "border-purple-500"
    when "pink"    then "border-pink-500"
    when "black"   then "border-gray-900"
    else                "border-line"
    end
  end
end
