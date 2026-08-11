# Public on purpose — no `authenticate_user!`. A help centre nobody
# signed out can read isn't much of a help centre, and nothing here is
# sensitive: the articles describe how the app works, not anything
# account-specific.
class HelpController < ApplicationController
  def index
    @articles_by_category = HelpArticle.by_category
  end

  def show
    @article = HelpArticle.find(params[:slug])
    raise ActiveRecord::RecordNotFound, "No help article #{params[:slug].inspect}" unless @article

    @articles_by_category = HelpArticle.by_category
  end
end
