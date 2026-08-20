# A help-centre article, backed by a markdown file with YAML front matter in
# app/views/help/articles/ rather than a database row. There's no reason to
# involve ActiveRecord for content that's written by hand and deployed with
# the app — grep, diff, and PR review all work better on files than on rows,
# and there's nothing here that benefits from a query.
class HelpArticle
  ARTICLES_DIR = Rails.root.join("app/views/help/articles")

  FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

  # Sidebar category order. Not alphabetical — it's the order a new user
  # actually moves through the app: get a board going, work inside it, then
  # the things that sit across boards, then the ambient stuff.
  CATEGORY_ORDER = [
    "Getting started",
    "Boards",
    "Lists",
    "Cards",
    "Collaboration",
    "Planner and map",
    "Finding things",
    "Appearance",
  ].freeze

  attr_reader :slug, :title, :category, :position, :body_markdown

  def self.all
    @all ||= Dir.glob(ARTICLES_DIR.join("*.md")).map { |path| new(path) }.sort_by(&:sort_key).freeze
  end

  def self.find(slug)
    all.find { |article| article.slug == slug.to_s }
  end

  # Grouped in CATEGORY_ORDER, articles within a category in `position`
  # order — a plain Hash preserves insertion order, so iterating this in
  # views renders both orderings for free.
  def self.by_category
    all.group_by(&:category)
  end

  def initialize(path)
    @slug = File.basename(path, ".md")
    front_matter, @body_markdown = self.class.parse(File.read(path))
    @title    = front_matter.fetch("title")    { raise "#{path} has no `title` in its front matter" }
    @category = front_matter.fetch("category") { raise "#{path} has no `category` in its front matter" }
    @position = front_matter.fetch("position", 0).to_i
  end

  # Default kramdown dialect, not GFM — GFM needs the separate
  # kramdown-parser-gfm gem, and nothing in these articles (no tables, no
  # strikethrough) needs it. Plain kramdown already handles everything used
  # here: headings, lists, links, bold/italic, inline code, and raw HTML
  # passthrough for the theme-swapped screenshots.
  def to_html
    Kramdown::Document.new(body_markdown, entity_output: :symbolic, syntax_highlighter: nil).to_html
  end

  # Every /help/:slug this article links to, in the order they appear —
  # read by the link-integrity test, not used at render time.
  def linked_slugs
    body_markdown.scan(%r{\]\(/help/([a-z0-9-]+)\)}).flatten
  end

  def sort_key
    category_rank = self.class::CATEGORY_ORDER.index(category) || self.class::CATEGORY_ORDER.size
    [category_rank, position, title]
  end

  def self.parse(raw)
    match = FRONT_MATTER.match(raw)
    return [{}, raw] unless match

    front_matter = YAML.safe_load(match[1]) || {}
    [front_matter, match[2]]
  end
end
