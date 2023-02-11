class CreateEpisodeTexts < ActiveRecord::Migration[7.0]
  def change
    create_table :episode_texts do |t|
      t.string :series
      t.string :episode
      t.text :text

      t.timestamps
    end
  end
end
