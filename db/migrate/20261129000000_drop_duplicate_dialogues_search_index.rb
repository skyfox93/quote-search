# dialogues had two identical GIN indexes on searchable. Keep
# index_dialogues_on_searchable (Rails' default name) and drop the other.
class DropDuplicateDialoguesSearchIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :dialogues, :searchable, name: "dialogues_search_index", using: :gin, if_exists: true
  end
end
