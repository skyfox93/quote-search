require "test_helper"

class EpisodeTextTest < ActiveSupport::TestCase
  test "normalize_title treats part numbering, punctuation and spelling alike" do
    same = ["Chain of Command, Part II", "Chain of Command, Part 2", "chain of command part two", "Chain Of Command (2)"]
    assert_equal 1, same.map { EpisodeText.normalize_title(_1) }.uniq.size
    assert_equal EpisodeText.normalize_title("The Measure Of A Man"), EpisodeText.normalize_title("Measure of a Man")
    assert_equal EpisodeText.normalize_title("Q Who"), EpisodeText.normalize_title("Q Who?")
  end

  test "ids_for_titles matches guessed titles within a series, in order" do
    mind = EpisodeText.create!(series: "TNG", episode: "episode 999", title: "The Mind's Eye", text: "x")
    darmok = EpisodeText.create!(series: "TNG", episode: "episode 998", title: "Darmok", text: "x")
    EpisodeText.create!(series: "DS9", episode: "episode 997", title: "Darmok", text: "x")

    assert_equal [darmok.id, mind.id], EpisodeText.ids_for_titles(["darmok", "Mind's Eye", "Nonexistent"], series: "TNG")
    assert_equal [], EpisodeText.ids_for_titles(["  ", ""])
  end

  test "short_number and header fields" do
    episode = EpisodeText.new(series: "TNG", season: 4, episode_number: 24,
                              text: "The Next Generation Transcripts - X    X Stardate: 44885.5 Original Airdate: 27 May, 1991         Log.")
    assert_equal "S4 · E24", episode.short_number
    assert_equal "44885.5", episode.stardate
    assert_equal "27 May, 1991", episode.airdate
    assert_equal "S1 · Pilot", EpisodeText.new(season: 1).short_number
    assert_nil EpisodeText.new.short_number
  end
end
