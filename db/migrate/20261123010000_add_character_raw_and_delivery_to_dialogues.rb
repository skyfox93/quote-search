# Keeps each line's speaker exactly as parsed from the transcript
# (character_raw) while `character` holds the standardized name, and records
# how the line was delivered ("OC", "on viewscreen") when the raw name said.
# Filled in by `bin/rails characters:standardize`.
class AddCharacterRawAndDeliveryToDialogues < ActiveRecord::Migration[8.1]
  def change
    add_column :dialogues, :character_raw, :string
    add_column :dialogues, :delivery, :string
    add_index :dialogues, [:series, :character]
  end
end
