require "test_helper"

class EpisodeChunkTest < ActiveSupport::TestCase
  test "no filters means no join" do
    assert_no_match(/episode_texts/, EpisodeChunk.filtered({}).to_sql)
  end

  test "filters use the episode_texts columns" do
    sql = EpisodeChunk.filtered(series: "TNG", season: 4, episode_number: 24).to_sql
    assert_match(/"episode_texts"."series" = 'TNG'/, sql)
    assert_match(/"episode_texts"."season" = 4/, sql)
    assert_match(/"episode_texts"."episode_number" = 24/, sql)
  end

  test "SQL in filter values is quoted, not executed" do
    attack = "TNG'; DROP TABLE episode_chunks; --"
    sql = EpisodeChunk.filtered(series: attack, title: attack).to_sql

    assert_includes sql, "'TNG''; DROP TABLE episode_chunks; --'"
    assert_includes sql, "ILIKE '%TNG''; DROP TABLE episode\\_chunks; --%'"
    assert_nothing_raised { EpisodeChunk.filtered(series: attack, title: attack).to_a }
  end

  test "LIKE wildcards in titles match literally" do
    sql = EpisodeChunk.filtered(title: "100%_done").to_sql
    assert_includes sql, "'%100\\%\\_done%'"
  end

  test "split makes overlapping chunks under the size limit" do
    text = (1..300).map { |i| "LINE #{i}: some dialogue here" }.join("\n")
    chunks = EpisodeChunk.split(text)

    assert chunks.all? { |c| c.length <= EpisodeChunk::CHUNK_SIZE }
    assert_includes chunks.first, "LINE 1:"
    assert_includes chunks.last, "LINE 300:"
  end
end
