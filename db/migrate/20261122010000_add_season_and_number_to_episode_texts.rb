class AddSeasonAndNumberToEpisodeTexts < ActiveRecord::Migration[8.1]
  def change
    add_column :episode_texts, :season, :integer
    add_column :episode_texts, :episode_number, :integer
  end
end
