class EpisodeText < ApplicationRecord
  has_many :episode_chunks, dependent: :delete_all
end
