# Keys that don't repeat across series. Season and episode numbers do ("season
# 4" is in TNG and DS9; "episode 74" is in several series), so grouping or
# counting by them alone silently merges series.
#
#   - episode_texts.season_id: e.g. "TNG S4", generated from series and season.
#   - dialogues.episode_id: the line's episode (episode_texts.id), so a line
#     joins to its episode on one column.
#   - dialogues.season_id: copied from the episode, so lines can be grouped by
#     season without a join.
#
# dialogues' two columns are filled by Dialogue.link_episodes, which the seeds
# and dialogues:rebuild call after inserting lines.
class AddSeasonIdAndEpisodeId < ActiveRecord::Migration[8.1]
  def up
    add_column :episode_texts, :season_id, :virtual, type: :string, stored: true,
               as: "series || ' S' || season::text"
    add_index :episode_texts, :season_id

    add_reference :dialogues, :episode, foreign_key: { to_table: :episode_texts }, index: true
    add_column :dialogues, :season_id, :string
    add_index :dialogues, :season_id

    execute <<~SQL
      UPDATE dialogues d SET episode_id = e.id, season_id = e.season_id
      FROM episode_texts e WHERE e.series = d.series AND e.episode = d.episode
    SQL
  end

  def down
    remove_column :dialogues, :season_id
    remove_reference :dialogues, :episode, foreign_key: { to_table: :episode_texts }, index: true
    remove_column :episode_texts, :season_id
  end
end
