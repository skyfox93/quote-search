class AddIndexToDialogues < ActiveRecord::Migration[7.0]
  def change
    add_column :dialogues, :index, :int
  end
end