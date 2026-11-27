# An embedding of each episode's summary, for scene search. With ~700 rows an
# exact scan is fast, so it has no vector index.
class AddSummaryEmbeddingToEpisodeTexts < ActiveRecord::Migration[8.1]
  def change
    add_column :episode_texts, :summary_embedding, :vector, limit: 1536
  end
end
