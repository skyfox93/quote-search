# Episode scripts are too long to embed whole, so each episode is split into
# chunks and each chunk gets its own pgvector embedding.
class CreateEpisodeChunks < ActiveRecord::Migration[7.0]
  def change
    enable_extension "vector"

    create_table :episode_chunks do |t|
      t.references :episode_text, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :episode_chunks, [:episode_text_id, :position], unique: true
    add_index :episode_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
