require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the index renders without signing in" do
    get help_index_path

    assert_response :success
  end

  test "the index lists every article" do
    get help_index_path

    HelpArticle.all.each do |article|
      assert_select "a[href='#{help_article_path(article.slug)}']", text: article.title, minimum: 1
    end
  end

  test "every article route resolves and renders, signed out" do
    HelpArticle.all.each do |article|
      get help_article_path(article.slug)

      assert_response :success, "GET /help/#{article.slug} did not render"
      assert_select "h1, h2", text: article.title
    end
  end

  test "every article also renders while signed in, alongside the normal top nav" do
    sign_in users(:one)

    HelpArticle.all.each do |article|
      get help_article_path(article.slug)
      assert_response :success
    end

    assert_select "header" # the normal top nav renders too, unlike signed-out
  end

  test "an unknown slug 404s" do
    get help_article_path("not-a-real-article")

    assert_response :not_found
  end

  test "every article slug in the sidebar resolves" do
    get help_index_path

    HelpArticle.all.each do |article|
      get help_article_path(article.slug)
      assert_response :success
    end
  end
end
