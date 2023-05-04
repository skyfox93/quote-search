class AddSearchableEnglish < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      ALTER TABLE dialogues
      ADD COLUMN searchable_english tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(line, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(character,'')), 'B')
      ) STORED;
    SQL
    add_index :dialogues, :searchable, using: :gin
  end

  def down
    remove_column :dialogue, :searchable
  end
end