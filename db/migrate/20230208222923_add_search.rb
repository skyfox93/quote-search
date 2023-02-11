class AddSearch < ActiveRecord::Migration[7.0]
      def up
        execute <<-SQL
          ALTER TABLE quotes
          ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
            setweight(to_tsvector('simple', coalesce(content, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(author,'')), 'B')
          ) STORED;
        SQL
        add_index :quotes, :searchable, using: :gin
      end
    
      def down
        remove_column :quotes, :searchable
      end
end
