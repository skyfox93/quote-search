Rails.application.routes.draw do
  root "home#index"

  resources :dialogues
  resources :episode_texts, only: [:index, :show] do
    get :results, on: :collection
    get :suggestion, on: :collection
  end
  get "search/summary", to: "search_summaries#show", as: :search_summary
  get "ask", to: "questions#index", as: :ask
  get "ask/stream", to: "questions#stream", as: :ask_stream
  resources :quotes, only: [:index]
end
