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

  # A scene of `n` lines, each "NAME: ..." about 40 characters long.
  def scene(location, n, name: "PICARD")
    ["[#{location}]  (they enter)", *(1..n).map { "#{name}: line #{_1} of the #{location.downcase} scene." }].join("\n")
  end

  test "split makes one chunk per scene, starting at its location" do
    text = [scene("Bridge", 15), scene("Ten Forward", 15), scene("Sickbay", 15)].join("\n")
    chunks = EpisodeChunk.split(text)

    assert_equal ["[Bridge]", "[Ten Forward]", "[Sickbay]"], chunks.map { _1[/\A\[[^\]]+\]/] }
    assert chunks.all? { text.include?(_1) }, "every chunk is an exact slice of the text"
  end

  test "a location in the middle of a line starts a scene, a delivery tag doesn't" do
    text = "RIKER: Captain? It's all  [Living room]  (a woman's face)\nELINE: Kamin.\nPICARD [OC]: Picard to Enterprise. #{"x" * 400}"
    chunks = EpisodeChunk.split("#{"teaser " * 70}\n#{text}")

    assert_equal 2, chunks.size
    assert chunks.last.start_with?("[Living room]")
    assert_includes chunks.last, "PICARD [OC]: Picard to Enterprise."
  end

  test "short scenes join the next one, and a short last scene joins the one before" do
    text = ["[Corridor]  (Picard walks)", scene("Bridge", 15), scene("Sickbay", 15), "[Turbolift]  (doors close)"].join("\n")
    chunks = EpisodeChunk.split(text)

    assert_equal 2, chunks.size
    assert chunks.first.start_with?("[Corridor]")
    assert_includes chunks.first, "[Bridge]"
    assert chunks.last.start_with?("[Sickbay]")
    assert chunks.last.end_with?("(doors close)")
  end

  test "split drops the transcript site's header" do
    header = "The Next Generation Transcripts - The Inner Light    The Inner Light Stardate: 45944.1 Original Airdate: 1 Jun, 1992    "
    chunks = EpisodeChunk.split(header + scene("Bridge", 15))

    assert_equal 1, chunks.size
    assert chunks.first.start_with?("[Bridge]")
    assert_not_includes chunks.first, "Inner Light"
  end

  test "a long scene is split into overlapping pieces of whole lines" do
    text = scene("Bridge", 300)
    lines = text.split("\n")
    chunks = EpisodeChunk.split(text)

    assert chunks.size > 1
    assert chunks.all? { |c| c.length <= EpisodeChunk::CHUNK_SIZE }
    assert_equal lines.first, chunks.first.lines.first.chomp
    assert_equal lines.last, chunks.last.lines.last.chomp
    chunks.each { |chunk| assert_empty chunk.lines.map(&:chomp) - lines, "every line is whole" }
    chunks.each_cons(2) do |a, b|
      shared = a.lines.map(&:chomp) & b.lines.map(&:chomp)
      assert shared.join("\n").length >= EpisodeChunk::CHUNK_OVERLAP - 50, "neighbours share about CHUNK_OVERLAP of whole lines"
    end
  end

  test "split still cuts a line that is too long to keep whole" do
    chunks = EpisodeChunk.split("PICARD: #{"word " * 2_000}")
    assert chunks.size > 1
    assert chunks.all? { |c| c.length <= EpisodeChunk::CHUNK_SIZE }
  end
end
