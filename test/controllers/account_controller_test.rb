require "test_helper"

class AccountControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    # Real avatar attaches here trigger Active Storage's analyze/transform
    # jobs via after_commit (Rails' transactional test fixtures fire commit
    # callbacks even though the transaction rolls back). This app's default
    # :async adapter would actually run those jobs in background threads
    # that can't see the not-really-committed row, retrying/blocking — the
    # :test adapter just queues them (perform_enqueued_jobs still works).
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = users(:one)
    @board_one = boards(:one)
    @list_one = lists(:one)
    # Fixture cards/lists/boards all default to the scaffold's literal
    # "MyString" — several tests below assert a specific title is/isn't
    # on the page, which is meaningless if every fixture shares the same
    # text. Rename this one card so its title is unambiguous.
    @card_one = cards(:one)
    @card_one.update!(title: "Card One Accessible")
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  # --- auth ---

  test "profile redirects unauthenticated users" do
    get account_profile_url
    assert_redirected_to new_user_session_url
  end

  test "activity redirects unauthenticated users" do
    get account_activity_url
    assert_redirected_to new_user_session_url
  end

  test "cards redirects unauthenticated users" do
    get account_cards_url
    assert_redirected_to new_user_session_url
  end

  test "settings redirects unauthenticated users" do
    get account_settings_url
    assert_redirected_to new_user_session_url
  end

  test "settings renders the login/security and danger zone controls" do
    sign_in @user
    get account_settings_url

    assert_response :success
    assert_select "a[href=?]", edit_user_registration_path
    assert_select "form[action=?]", account_deactivate_path
  end

  test "bare /account redirects to profile" do
    sign_in @user
    get account_url
    assert_redirected_to account_profile_url
  end

  # --- notification preferences ---

  test "settings renders a toggle row for every preference type, checked by default" do
    sign_in @user
    get account_settings_url

    assert_response :success
    assert_select "form[action=?]", account_settings_path do
      Notification::PREFERENCE_TYPES.each do |type, meta|
        assert_select "input[type=checkbox][name=?][checked]", "user[notification_preferences][#{type}]"
        assert_select "*", text: meta[:title]
      end
    end
  end

  test "update_settings redirects unauthenticated users" do
    patch account_settings_url, params: { user: { notification_preferences: { "comment" => "0" } } }
    assert_redirected_to new_user_session_url
  end

  test "update_settings persists an unchecked box as false and leaves the others true" do
    sign_in @user

    patch account_settings_url, params: {
      user: { notification_preferences: { "mention" => "1", "added_to_card" => "1" } }
    }

    assert_redirected_to account_settings_url
    @user.reload
    assert_equal false, @user.notification_preferences["comment"]
    assert_equal true, @user.notification_preferences["mention"]
    assert_equal true, @user.notification_preferences["added_to_card"]
    assert @user.notifies?(:mention)
    assert_not @user.notifies?(:comment)
  end

  # --- profile ---

  test "profile renders" do
    sign_in @user
    get account_profile_url

    assert_response :success
    assert_select "form[action=?]", account_profile_path
  end

  test "profile shows initials and an Add photo control when no avatar is attached" do
    sign_in @user
    assert_not @user.avatar.attached?

    get account_profile_url

    assert_response :success
    assert_select "img[alt=?]", @user.display_name, count: 0
    assert_select "div", text: @user.initials
    assert_select "label", text: "Add photo"
    assert_select "button", text: "Remove", count: 0
  end

  test "profile shows the photo and Change/Remove controls when an avatar is attached" do
    sign_in @user
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )

    get account_profile_url

    assert_response :success
    assert_select "img[alt=?]", @user.display_name
    assert_select "label", text: "Change photo"
    assert_select "button", text: "Remove"
  end

  test "profile updates the name" do
    sign_in @user
    patch account_profile_url, params: { user: { name: "New Name" } }

    assert_redirected_to account_profile_url
    assert_equal "New Name", @user.reload.name

    follow_redirect!
    assert_match "Profile updated.", response.body
  end

  test "a :notice flash renders with success styling" do
    sign_in @user
    patch account_profile_url, params: { user: { name: "New Name" } }
    follow_redirect!

    assert_select "#flash div.bg-success-100.text-success-600" do
      assert_select "i.fa-circle-check"
      assert_select "span", text: "Profile updated."
    end
  end

  test "profile shows an inline error for a blank name and does not save it" do
    sign_in @user
    @user.update_column(:name, "Existing Name")

    patch account_profile_url, params: { user: { name: "" } }

    assert_response :unprocessable_entity
    assert_equal "Existing Name", @user.reload.name
  end

  test "profile form cannot mass-assign email" do
    sign_in @user
    original_email = @user.email

    patch account_profile_url, params: { user: { name: "New Name", email: "hacked@example.com" } }

    assert_redirected_to account_profile_url
    assert_equal original_email, @user.reload.email
    assert_equal "New Name", @user.name
  end

  # --- avatar ---

  test "update_avatar redirects unauthenticated users" do
    patch account_avatar_url, params: { user: { avatar: fixture_file_upload("test.png", "image/png") } }
    assert_redirected_to new_user_session_url
  end

  test "destroy_avatar redirects unauthenticated users" do
    delete account_avatar_url
    assert_redirected_to new_user_session_url
  end

  test "update_avatar attaches a valid png and redirects with a notice" do
    sign_in @user
    file = fixture_file_upload("test.png", "image/png")

    patch account_avatar_url, params: { user: { avatar: file } }

    assert_redirected_to account_profile_url
    assert @user.reload.avatar.attached?
    follow_redirect!
    assert_match "Photo updated.", response.body
  end

  test "update_avatar rejects the wrong content type and does not attach" do
    sign_in @user
    # Genuinely non-image bytes — the model validation checks Active
    # Storage's sniffed blob.content_type (post-attach), not the client's
    # declared header, so relabeling real image bytes wouldn't fool it.
    text_file = Tempfile.new(["not_an_image", ".txt"])
    begin
      text_file.write("just plain text, not an image")
      text_file.rewind
      file = Rack::Test::UploadedFile.new(text_file.path, "text/plain")

      patch account_avatar_url, params: { user: { avatar: file } }

      assert_redirected_to account_profile_url
      assert_not @user.reload.avatar.attached?
      follow_redirect!
      assert_match "PNG, JPEG, or WebP", response.body
    ensure
      text_file.close
      text_file.unlink
    end
  end

  test "update_avatar rejects a file over 5 MB and does not attach" do
    sign_in @user

    oversized = Tempfile.new(["oversized", ".png"])
    begin
      oversized.write("a" * 6.megabytes)
      oversized.rewind

      patch account_avatar_url, params: { user: { avatar: Rack::Test::UploadedFile.new(oversized.path, "image/png") } }

      assert_redirected_to account_profile_url
      assert_not @user.reload.avatar.attached?
      follow_redirect!
      assert_match "smaller than 5 MB", response.body
    ensure
      oversized.close
      oversized.unlink
    end
  end

  # The mandatory demo trap: update_profile's context: :profile_update
  # requires a non-blank name, which a demo/nameless user doesn't have.
  # update_avatar must use a plain save so an avatar-only upload never
  # trips that unrelated validation.
  test "update_avatar succeeds for a user with a nil name" do
    demo = User.create!(email: "demo-trap@example.com", password: "password")
    assert_nil demo[:name]
    sign_in demo

    file = fixture_file_upload("test.png", "image/png")
    patch account_avatar_url, params: { user: { avatar: file } }

    assert_redirected_to account_profile_url
    assert demo.reload.avatar.attached?
  end

  test "update_avatar cannot mass-assign name or email" do
    sign_in @user
    original_name = @user.name
    original_email = @user.email
    file = fixture_file_upload("test.png", "image/png")

    patch account_avatar_url, params: { user: { avatar: file, name: "Hacked", email: "hacked@example.com" } }

    assert_redirected_to account_profile_url
    assert @user.reload.avatar.attached?
    assert_equal original_name, @user.name
    assert_equal original_email, @user.email
  end

  test "destroy_avatar purges an attached photo" do
    sign_in @user
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )

    perform_enqueued_jobs do
      delete account_avatar_url
    end

    assert_redirected_to account_profile_url
    assert_not @user.reload.avatar.attached?
    follow_redirect!
    assert_match "Photo removed.", response.body
  end

  test "destroy_avatar is a no-op when nothing is attached" do
    sign_in @user
    assert_not @user.avatar.attached?

    delete account_avatar_url

    assert_redirected_to account_profile_url
  end

  # --- activity ---

  test "activity lists the user's own activities on accessible cards" do
    sign_in @user
    get account_activity_url

    assert_response :success
    assert_match @card_one.title, response.body
  end

  test "activity excludes activity on a card whose board is no longer accessible" do
    # Simulates a user who acted on a card, then lost access to that board —
    # the activity row survives (dependent: :nullify / never destroyed) but
    # the card is out of reach, so linking it would 404. A fresh board/list/
    # card (not a shared fixture) so its title can't collide with anything
    # else legitimately on the page.
    other_owner = users(:two)
    inaccessible_board = other_owner.boards.create!(name: "Inaccessible Board")
    inaccessible_list = inaccessible_board.lists.create!(name: "Inaccessible List", position: 1)
    inaccessible_card = inaccessible_list.cards.create!(title: "Card Nobody Else Should See")
    Activity.create!(user: @user, card: inaccessible_card, action: "created")

    sign_in @user
    get account_activity_url

    assert_response :success
    assert_no_match inaccessible_card.title, response.body
  end

  test "activity never renders another user's activities" do
    sign_in users(:two)
    get account_activity_url

    assert_response :success
    assert_no_match @card_one.title, response.body
  end

  test "activity query count stays flat as activity count grows" do
    small = count_queries_for_account_activity(activity_count: 5)
    large = count_queries_for_account_activity(activity_count: 10)

    assert_operator small, :<=, 12
    assert_equal small, large, "query count must not grow with activity count (N+1 regression)"
  end

  # --- cards ---

  test "cards shows only cards the user is assigned to and can still access" do
    sign_in @user

    accessible_card = @list_one.cards.create!(title: "Assigned And Accessible")
    CardMember.create!(card: accessible_card, user: @user)

    # A stale assignment on a card whose board this user has no access to —
    # a fresh board/list/card, not the shared fixture, so the title can't
    # collide with anything else on the page.
    other_owner = users(:two)
    inaccessible_board = other_owner.boards.create!(name: "Other Owner Board")
    inaccessible_list = inaccessible_board.lists.create!(name: "Other Owner List", position: 1)
    inaccessible_card = inaccessible_list.cards.create!(title: "Stale Assignment Card")
    CardMember.create!(card: inaccessible_card, user: @user)

    get account_cards_url

    assert_response :success
    assert_match accessible_card.title, response.body
    assert_no_match inaccessible_card.title, response.body
  end

  test "cards excludes archived cards" do
    sign_in @user

    archived_card = @list_one.cards.create!(title: "Archived Assigned Card", archived_at: Time.current)
    CardMember.create!(card: archived_card, user: @user)

    get account_cards_url

    assert_response :success
    assert_no_match archived_card.title, response.body
  end

  test "cards marks completed rows with a filled check button and leaves incomplete rows unmarked at rest" do
    sign_in @user
    @card_one.update!(completed: true)

    incomplete_card = @list_one.cards.create!(title: "Incomplete Assigned Card")
    CardMember.create!(card: incomplete_card, user: @user)

    get account_cards_url

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@card_one, :account_row)}" do
      assert_select "button.bg-success-600 i.fa-check"
      assert_select "span.sr-only", text: "Completed."
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(incomplete_card, :account_row)}" do
      assert_select "button.bg-success-600", count: 0
      assert_select "span.sr-only", count: 0
      # At rest the reveal wrapper is collapsed to w-0 — still present in
      # the DOM (for the hover/focus-within reveal) but reserves no space.
      assert_select "button[aria-label=?]", "Mark complete", count: 1
    end
  end

  test "a plain GET of the cards page never carries the one-shot completion pop, even with completed cards present" do
    sign_in @user
    @card_one.update!(completed: true)

    get account_cards_url

    assert_response :success
    assert_no_match(/animate-complete-pop/, response.body)
  end

  test "cards empty state renders when nothing is assigned" do
    # The fixture set assigns @user to @card_one via card_members.yml —
    # clear it so this test genuinely exercises the zero-cards case.
    CardMember.where(user: @user).destroy_all

    sign_in @user
    get account_cards_url

    assert_response :success
    assert_match "not assigned to any cards", response.body
  end

  test "cards page subscribes to the signed-in user's own per-user cards stream" do
    sign_in @user
    get account_cards_url

    assert_response :success
    expected_signed_name = Turbo::StreamsChannel.signed_stream_name([@user, :cards])
    assert_select "turbo-cable-stream-source[signed-stream-name=?]", expected_signed_name
  end

  test "cards sort flips between due date and recently updated" do
    sign_in @user

    get account_cards_url(sort: "updated")
    assert_response :success

    get account_cards_url(sort: "due")
    assert_response :success
  end

  # --- close (✕) return-to stash ---

  test "visiting an account page from a board stashes it as the return-to path" do
    sign_in @user
    get account_profile_url, headers: { "HTTP_REFERER" => board_url(@board_one) }

    assert_equal board_path(@board_one), session[:account_return_to]
  end

  test "navigating between account tabs does not overwrite the stashed return-to path" do
    sign_in @user
    get account_profile_url, headers: { "HTTP_REFERER" => board_url(@board_one) }
    get account_activity_url, headers: { "HTTP_REFERER" => account_profile_url }

    assert_equal board_path(@board_one), session[:account_return_to]
  end

  test "close button links to the stashed return-to path" do
    sign_in @user
    get account_profile_url, headers: { "HTTP_REFERER" => board_url(@board_one) }

    assert_select "a[aria-label=?][href=?]", "Close settings", board_path(@board_one)
  end

  test "close button falls back to boards_path with no referer stashed" do
    sign_in @user
    get account_profile_url

    assert_select "a[aria-label=?][href=?]", "Close settings", boards_path
  end

  test "an external referer is not stashed (open-redirect guard)" do
    sign_in @user
    get account_profile_url, headers: { "HTTP_REFERER" => "https://evil.example.com/phish" }

    assert_nil session[:account_return_to]
  end

  # --- deactivate ---

  test "deactivate strips access, signs out, and blocks re-authentication" do
    # A throwaway user, never the seeded demo user, per the brief.
    throwaway = User.create!(email: "throwaway@example.com", password: "password")
    throwaway.boards.create!(name: "Throwaway Board")
    sign_in throwaway

    patch account_deactivate_url

    assert_redirected_to new_user_session_url
    assert throwaway.reload.deactivated?

    # Signed out: a subsequent request to an authenticated page redirects to sign-in.
    get account_profile_url
    assert_redirected_to new_user_session_url

    # Cannot re-authenticate at all, even with the correct password — Devise's
    # failure app redirects back to sign-in (not a 200 re-render) with the
    # active_for_authentication?/inactive_message override's flash.
    post user_session_url, params: { user: { email: throwaway.email, password: "password" } }
    assert_redirected_to new_user_session_url
    follow_redirect!
    assert_match "deactivated", response.body
  end

  private

  def count_queries_for_account_activity(activity_count:)
    user = User.create!(email: "activityperf#{activity_count}@example.com", password: "password")
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test.png")),
      filename: "avatar.png", content_type: "image/png"
    )
    sign_in user

    board = user.boards.create!(name: "Activity Perf Board")
    list = board.lists.create!(name: "List", position: 1)

    activity_count.times do |i|
      card = list.cards.create!(title: "Card #{i}")
      Activity.create!(user: user, card: card, action: "created")
    end

    result = count_queries { get account_activity_url }
    assert_response :success
    sign_out user
    result
  end
end
