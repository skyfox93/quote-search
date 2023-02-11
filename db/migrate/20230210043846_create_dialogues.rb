class CreateDialogues < ActiveRecord::Migration[7.0]
  def change
    create_table :dialogues do |t|
      t.string :line
      t.string :episode
      t.string :series
      t.string :character

      t.timestamps
    end
  end
end
