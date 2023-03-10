class AddSearchToDialogue < ActiveRecord::Migration[7.0]
    def up
      execute <<-SQL
        ALTER TABLE dialogues
        ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
          setweight(to_tsvector('simple', coalesce(line, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(character,'')), 'B')
        ) STORED;
      SQL
      add_index :dialogues, :searchable, using: :gin
    end
  
    def down
      remove_column :dialogue, :searchable
    end
end
