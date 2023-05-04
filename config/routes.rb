Rails.application.routes.draw do
  resources :dialogues
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Defines the root path route ("/")
  root "dialogues#index"
  resources :episode_texts, only: [:index, :show]
  resources :quotes, only: [:index, :show]

end
