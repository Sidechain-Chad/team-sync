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
  # inner edges, so consecutive cells in the SAME row read as one continuous
  # bar — negative margins bleed the fill across the day cell's own padding
  # to close the gutter between them. :point returns the untouched chip
  # classes — the pre-start_date look, byte for byte.
  #
  # Row edges are the exception: the grid is 42 independent cells, so a
  # :middle/:end segment landing on Sunday (grid column 1) has no cell to its
  # left in the same row to bleed toward, and a :start/:middle segment on
  # Saturday (column 7) has none to its right — bleeding there ran the fill
  # past the cell's own edge with nothing on the other side to meet it,
  # instead of just capping it. Rounding the cap at a row edge, the same way
  # a real :start/:end already does, is what makes each row's portion of a
  # wrapped range read as a clean segment of one continuing bar rather than a
  # cut-off fragment.
  def planner_chip_or_bar_classes(card, day)
    fill = planner_chip_fill_classes(card)
    segment = planner_segment(card, day)
    return "#{planner_chip_classes(card)} rounded" if segment == :point

    cap_left  = segment == :start || day.sunday?
    cap_right = segment == :end   || day.saturday?

    classes = [fill]
    classes << "border-l-4 #{planner_chip_stripe_class(card)}" if segment == :start
    classes << (cap_left  ? "rounded-l" : "rounded-l-none -ml-1.5")
    classes << (cap_right ? "rounded-r" : "rounded-r-none -mr-1.5")
    classes.join(" ")
  end

  # A range card's full span, for the agenda row: "Aug 3–5" within one month,
  # "Jul 28 – Aug 26" across months. Uses the app's existing date convention
  # (`%b %-d`, en-dash) — same pieces the grid chip's title attribute already
  # builds, just collapsing the repeated month name.
  #
  # DELIBERATELY the card's true start..due, never clipped to the visible window.
  # The agenda repeats a range card on every day it spans, so the label is what
  # tells a viewer those rows are one card; a window-clipped label would misstate
  # the card's actual dates.
  #
  # Returns nil for anything that isn't a real span — no start date, or start and
  # due on the same calendar day — so the caller falls back to the due time. That
  # matches planner_segment's :point treatment in the grid: a same-day range is a
  # point, not a one-day bar.
  def planner_span_label(card)
    return nil unless card.date_range?

    first_day = card.start_date.to_date
    last_day  = card.due_date.to_date
    return nil if first_day == last_day

    if first_day.year == last_day.year && first_day.month == last_day.month
      "#{first_day.strftime('%b %-d')}–#{last_day.strftime('%-d')}"
    else
      "#{first_day.strftime('%b %-d')} – #{last_day.strftime('%b %-d')}"
    end
  end

  # Which part a given agenda row plays for a range card: :starts, :due or
  # :in_progress. nil for anything that isn't a real span — a point occupies one
  # row and needs no explanation.
  #
  # This exists because collapsing raised a question the old every-day listing
  # didn't: why does this card appear on Aug 2 and Aug 20 but not Aug 11? At three
  # rows a one-word marker answers that cheaply; at twenty-two it would have been
  # noise, which is why it wasn't worth adding before.
  #
  # Precedence is due > starts > in_progress: when today IS the due day the row
  # reads "due" (the more actionable fact), and when today is the start day it
  # reads "starts".
  def planner_agenda_role(card, day)
    return nil unless card.date_range?

    first_day = card.start_date.to_date
    last_day  = card.due_date.to_date
    return nil if first_day == last_day

    return :due    if day == last_day
    return :starts if day == first_day
    :in_progress
  end

  AGENDA_ROLE_LABELS = {
    starts:      "starts",
    in_progress: "in progress",
    due:         "due"
  }.freeze

  def planner_agenda_role_label(card, day)
    AGENDA_ROLE_LABELS[planner_agenda_role(card, day)]
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
