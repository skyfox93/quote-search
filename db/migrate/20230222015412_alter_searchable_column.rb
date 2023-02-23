class AlterSearchableColumn < ActiveRecord::Migration[7.0]
      def up
        remove_column :dialogue, :searchable
        execute <<-SQL
          ALTER TABLE dialogues
          ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
            setweight(to_tsvector('english', coalesce(line, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(character,'')), 'B')
          ) STORED;
        SQL
        add_index :dialogues, :searchable, using: :gin
      end
end
