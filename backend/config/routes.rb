Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Accept ヘッダーのないリクエストでも html ではなく jbuilder のテンプレートを探させる
  defaults format: :json do
    namespace :auth do
      resource :signup, only: :create
      post :login, to: "sessions#create"
      resource :session, only: :destroy
    end

    resource :me, only: :show, controller: :me
    namespace :me do
      resources :balloons, only: :index
    end

    resources :balloons, only: :create do
      scope module: :balloons do
        resources :plays, only: :create
        resource :collection, only: :create, path: "collect"
        resource :pop, only: :create
      end
    end
  end
end
