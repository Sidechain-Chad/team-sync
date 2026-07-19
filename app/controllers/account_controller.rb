class AccountController < ApplicationController
  before_action :authenticate_user!
  before_action :stash_return_to, only: [:profile, :activity, :cards, :settings]

  def profile
  end

  def update_profile
    current_user.assign_attributes(profile_params)

    if current_user.save(context: :profile_update)
      # Turbo Drive requires a 200 response to a form submission to be a
      # redirect (a bare `render` throws "Form responses must redirect to
      # another location") — the shared flash partial renders :notice now,
      # so the confirmation just rides the normal flash instead of a
      # query param.
      redirect_to account_profile_path, notice: "Profile updated."
    else
      render :profile, status: :unprocessable_entity
    end
  end

  # Activities are historical (kept even after board access is lost — see
  # User#activities `dependent: :nullify`), but a card's board can be left,
  # deleted, or otherwise fall out of reach after the activity happened.
  # Scoping to `current_user.all_cards` (the same access check every other
  # card read in the app uses) keeps this feed from linking a card the
  # user would 404 on if they clicked through.
  def activity
    # Every row renders current_user's own avatar — the same in-memory
    # object each time, so Rails' association caching already makes this
    # a single query total regardless of activity count; no includes needed.
    @activities = current_user.activities
                               .where(card_id: current_user.all_cards.select(:id))
                               .includes(card: { list: :board })
                               .order(created_at: :desc)
                               .limit(50)
  end

  def cards
    @sort = params[:sort] == "updated" ? "updated" : "due"

    # assigned_cards is every card this user is a member of; intersecting
    # with all_cards drops any assignment left over from a board they no
    # longer have access to (e.g. removed as a member without the
    # assignment itself being cleaned up).
    scope = current_user.assigned_cards
                         .active
                         .where(id: current_user.all_cards.select(:id))
                         .includes(:labels, list: :board)

    @cards = if @sort == "updated"
               scope.order(updated_at: :desc)
             else
               # due_date ASC already sorts NULLs last in Postgres; completed
               # ASC (false before true) pushes completed cards to the very
               # end regardless of their due date.
               scope.order(Arel.sql("completed ASC, due_date ASC"))
             end
  end

  def settings
  end

  # Deliberately a plain `save` (no :profile_update context) — that context
  # requires a non-blank name, which the demo user (and anyone else who's
  # never set one) doesn't have. Riding that context here would make an
  # avatar-only upload fail for them on an unrelated validation.
  def update_avatar
    current_user.avatar.attach(avatar_params[:avatar])

    if current_user.save
      redirect_to account_profile_path, notice: "Photo updated."
    else
      current_user.avatar.purge
      redirect_to account_profile_path, alert: current_user.errors[:avatar].first
    end
  end

  def destroy_avatar
    if current_user.avatar.attached?
      current_user.avatar.purge_later
      redirect_to account_profile_path, notice: "Photo removed."
    else
      redirect_to account_profile_path
    end
  end

  def deactivate
    current_user.deactivate!
    flash[:alert] = "Your account has been deactivated. You won't be able to sign back in."
    sign_out current_user
    redirect_to new_user_session_path
  end

  private

  def profile_params
    params.require(:user).permit(:name)
  end

  def avatar_params
    params.require(:user).permit(:avatar)
  end

  # Remembers where to send the ✕ button. Only stashes on entry: a referer
  # that's itself an /account/* path means the user is just moving between
  # tabs, so the ORIGINAL entry point (a board, most likely) is left alone
  # rather than getting overwritten with the previous account page. Only a
  # same-host referer is trusted — an external one is rejected so the ✕
  # can never be turned into an open redirect.
  def stash_return_to
    referer = request.referer
    return if referer.blank?

    begin
      uri = URI.parse(referer)
    rescue URI::InvalidURIError
      return
    end

    return if uri.host != request.host
    return if uri.path.start_with?("/account")

    session[:account_return_to] = uri.query.present? ? "#{uri.path}?#{uri.query}" : uri.path
  end
end
