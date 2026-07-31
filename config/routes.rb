Rails.application.routes.draw do
  # 1. Standard Devise routes for Users
  devise_for :users

  # 2. Root path (Home page)
  root 'boards#index'
  get "planner"        => "planner#index",  as: :planner
  get "planner/panel"  => "planner#panel",  as: :planner_panel
  get "planner/map"    => "planner#map",    as: :planner_map
  get "switch_boards"  => "boards#switcher", as: :switch_boards
  get "search"         => "search#index",   as: :search

  resources :notifications, only: [:index] do
    member do
      get :read
    end
    collection do
      patch :read_all
    end
  end

  # Personal Settings (account dropdown). Root redirects to profile so
  # linking bare "/account" (e.g. from a bookmark) lands somewhere real.
  get   "account",            to: redirect("/account/profile")
  get   "account/profile",    to: "account#profile",        as: :account_profile
  patch "account/profile",    to: "account#update_profile"
  get   "account/activity",   to: "account#activity",       as: :account_activity
  get   "account/cards",      to: "account#cards",          as: :account_cards
  get   "account/settings",   to: "account#settings",       as: :account_settings
  patch "account/settings",   to: "account#update_settings"
  patch "account/deactivate", to: "account#deactivate",     as: :account_deactivate
  patch  "account/avatar",    to: "account#update_avatar",  as: :account_avatar
  delete "account/avatar",    to: "account#destroy_avatar"

  # 3. Health check (Standard Rails 7.1+)
  get "up" => "rails/health#show", as: :rails_health_check

  # --- APP RESOURCES ---

  resources :boards do
    resources :lists, only: [:create, :update, :destroy]
    resources :board_users, only: [:create, :destroy]
    resources :labels, only: [:new, :create, :edit, :update, :destroy]

    # #closed lists the user's closed boards. On the collection, not a member,
    # and declared BEFORE the member routes so /boards/closed can't be swallowed
    # by the :id segment of resources' own show route.
    collection do
      get :closed
    end

    member do
      get :archive
      get :activity
      get :map
      patch :toggle_favorite
      # Close/reopen the whole board. NOT named :archive — that member route
      # already exists above and means "show this board's archived CARDS".
      patch :close
      patch :reopen
    end
  end

  # Cancel routes for the inline label edit/create forms.
  get "cards/:card_id/labels/:label_id/cancel_edit", to: "labels#cancel_edit", as: :label_row_cancel
  get "cards/:card_id/labels/cancel_new",            to: "labels#cancel_new",  as: :new_label_cancel

  # Lists
  resources :lists do
    member do
      patch :move
      patch :sort
      patch :archive_all_cards
    end
    resources :cards, only: [:new, :create]
  end

  # Cards (Top level access)
  resources :cards, only: [:edit, :update, :destroy, :show] do
    resources :members, only: [:create, :destroy], controller: 'card_members', param: :user_id
    resources :comments, only: [:create, :destroy]
    resources :labels, only: [:create, :destroy], controller: 'card_labels', param: :label_id
    
    # No :update — a checklist title has no rename UI, so the action was dead
    # code with an unchecked save in it (see ChecklistsController).
    resources :checklists, only: [:create, :destroy] do
      resources :checklist_items, only: [:create, :update, :destroy]
    end
    resources :attachments, only: [:create, :destroy]

    member do
      patch :move
      post  :copy
      get   :edit_description
      patch :update_description
      get   :edit_title
      patch :update_title
      patch :archive
      patch :unarchive
      patch :toggle_complete
      # Per-user card subscription. Named like boards#toggle_favorite, the
      # closest precedent — same shape: one join row, created or destroyed.
      patch :toggle_watch
    end
  end
end
