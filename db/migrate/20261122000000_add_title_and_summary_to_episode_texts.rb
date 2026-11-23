class AddTitleAndSummaryToEpisodeTexts < ActiveRecord::Migration[8.1]
  def change
    add_column :episode_texts, :title, :string
    add_column :episode_texts, :summary, :text
    add_index :episode_texts, [:series, :episode]
  end
end
