Rails.application.routes.draw do
  get 'lists/create'
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :boards, only: [:show]

  resources :boards, only: [:show] do
    # This creates POST /boards/:board_id/lists
    resources :lists, only: [:create]
  end

  resources :lists do
      resources :cards, only: [:create]
    end

    resources :cards do
      member do
        patch :move # Creates a route: PATCH /cards/:id/move
      end
    end

  root 'boards#index' # or wherever you want the home page
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
