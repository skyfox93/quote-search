Rails.application.routes.draw do
  root "home#index"
  get "examples/:level", to: "home#example", as: :landing_example, constraints: { level: /keyword|rag|agent/ }

  resources :dialogues
  resources :episode_texts, only: [:index, :show] do
    get :results, on: :collection
  end
  get "search/summary", to: "search_summaries#show", as: :search_summary
  get "ask", to: "questions#index", as: :ask
  get "ask/stream", to: "questions#stream", as: :ask_stream
  resources :quotes, only: [:index]
end
