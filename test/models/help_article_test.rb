require "test_helper"

class HelpArticleTest < ActiveSupport::TestCase
  test "loads at least the expected article count" do
    assert_operator HelpArticle.all.size, :>=, 12, "expected 12-15 help articles, see the report for the final list"
  end

  test "every article has a title, category, and non-empty body" do
    HelpArticle.all.each do |article|
      assert article.title.present?, "#{article.slug} has no title"
      assert article.category.present?, "#{article.slug} has no category"
      assert article.body_markdown.present?, "#{article.slug} has an empty body"
    end
  end

  test "every article's category is in the known display order" do
    HelpArticle.all.each do |article|
      assert_includes HelpArticle::CATEGORY_ORDER, article.category,
        "#{article.slug}'s category #{article.category.inspect} is not in HelpArticle::CATEGORY_ORDER"
    end
  end

  test "slugs are unique" do
    slugs = HelpArticle.all.map(&:slug)
    assert_equal slugs.uniq.size, slugs.size, "duplicate slug among help articles"
  end

  test "find returns nil for an unknown slug rather than raising" do
    assert_nil HelpArticle.find("does-not-exist")
  end

  test "by_category groups every article exactly once" do
    grouped = HelpArticle.by_category
    total = grouped.values.sum(&:size)
    assert_equal HelpArticle.all.size, total
  end

  # THE assertion that stops the sidebar and the prose from rotting apart:
  # every /help/:slug an article links to has to resolve to a real article.
  test "every internal help link points at an article that exists" do
    known_slugs = HelpArticle.all.map(&:slug)

    HelpArticle.all.each do |article|
      article.linked_slugs.each do |linked_slug|
        assert_includes known_slugs, linked_slug,
          "#{article.slug} links to /help/#{linked_slug}, which does not exist"
      end
    end
  end

  test "parses front matter and leaves it out of the rendered body" do
    front_matter, body = HelpArticle.parse(<<~MD)
      ---
      title: Example
      category: Getting started
      ---
      Body text.
    MD

    assert_equal "Example", front_matter["title"]
    assert_equal "Body text.", body.strip
  end

  test "a file with no front matter is treated as a plain body" do
    front_matter, body = HelpArticle.parse("Just text, no front matter.")

    assert_equal({}, front_matter)
    assert_equal "Just text, no front matter.", body
  end
end
