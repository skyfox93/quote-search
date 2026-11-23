Rails.application.routes.draw do
  root "dialogues#index"

  resources :dialogues
  resources :episode_texts, only: [:index, :show] do
    get :results, on: :collection
  end
  get "search/summary", to: "search_summaries#show", as: :search_summary
  resources :quotes, only: [:index, :show]
end
