require "test_helper"

# Scaffolding-level coverage only — this commit has no articles yet (see the
# report for why they're split into their own commit). Content-dependent
# assertions (every article resolves, every link resolves, the index lists
# everything) land alongside the articles themselves, since they're
# meaningless against zero content.
class HelpControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the index renders without signing in, even with no articles yet" do
    get help_index_path

    assert_response :success
  end

  test "the index also renders while signed in, alongside the normal top nav" do
    sign_in users(:one)

    get help_index_path

    assert_response :success
    assert_select "header"
  end

  test "an unknown slug 404s" do
    get help_article_path("not-a-real-article")

    assert_response :not_found
  end
end
