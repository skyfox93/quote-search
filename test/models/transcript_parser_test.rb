require "test_helper"

class TranscriptParserTest < ActiveSupport::TestCase
  RAW = <<~TEXT
    \n\nThe Next Generation Transcripts - Q Who?\n\nQ Who?\nStardate:\n42761.3\nOriginal Airdate: 8 May, 1989\n
    Captain's log, stardate 42761.3. We are en route
    to Starbase one eight five.

    [Turbolift]

    PICARD: Deck nine. Officers' quarters. It's a meeting the Captain won't soon
    forget.
    (But instead of a deck, he steps out into a
    shuttlecraft in space)
    Q: Welcome, Picard, to shuttlecraft six.
    PICARD: Q.
    RO: Captain.
    DATA [OC]: Data to Picard.
    JANEWAY
    [OC]: Anything in Astrometrics?
    WORF: We must (beat) hold our
    position.
    (Kes leaves.)KES: Neelix!
    DATA: Computer: request all biographical information.
    <Back to the episode listing
    Star Trek ® is copyright of CBS Studios Inc.
  TEXT

  def blocks = TranscriptParser.parse(RAW)
  def speeches = blocks.reject(&:scene?).map { [_1.character_raw, _1.text] }

  test "finds every speaker at the start of a line, including one-letter names" do
    assert_equal [
      ["PICARD", "Deck nine. Officers' quarters. It's a meeting the Captain won't soon forget."],
      ["Q", "Welcome, Picard, to shuttlecraft six."],
      ["PICARD", "Q."],
      ["RO", "Captain."],
      ["DATA [OC]", "Data to Picard."],
      ["JANEWAY [OC]", "Anything in Astrometrics?"],
      ["WORF", "We must (beat) hold our position."],
      ["KES", "Neelix!"],
      ["DATA", "Computer: request all biographical information."]
    ], speeches
  end

  test "keeps the header, locations and stage directions as SCENE blocks" do
    scenes = blocks.select(&:scene?).map(&:text)

    assert scenes.first.start_with?("The Next Generation Transcripts - Q Who?")
    assert_includes scenes.first, "Captain's log, stardate 42761.3. We are en route to Starbase one eight five."
    assert_includes scenes, "[Turbolift]"
    assert_includes scenes, "(But instead of a deck, he steps out into a shuttlecraft in space)"
    assert_includes scenes, "(Kes leaves.)"
  end

  test "drops the transcript site's footer" do
    assert_no_match(/Back to the episode listing|copyright/, blocks.map(&:text).join(" "))
  end

  test "numbers blocks in order and rebuilds the transcript one block per line" do
    assert_equal (0...blocks.size).to_a, blocks.map(&:index)
    text = TranscriptParser.new(RAW).text
    assert_includes text, "\nQ: Welcome, Picard, to shuttlecraft six.\n"
    assert_includes text, "\nDATA [OC]: Data to Picard.\n"
  end

  test "dialogue rows carry standardized names, the name as written, and delivery" do
    rows = TranscriptParser.new(RAW).dialogue_rows(series: "TNG", episode: "episode 40")
    data = rows.find { _1[:character_raw] == "DATA [OC]" }
    scene = rows.find { _1[:line] == "[Turbolift]" }

    assert_equal({ series: "TNG", episode: "episode 40", character: "DATA", character_raw: "DATA [OC]", delivery: "OC", line: "Data to Picard." },
                 data.slice(:series, :episode, :character, :character_raw, :delivery, :line))
    assert_equal "SCENE", scene[:character]
    assert_includes rows.map { _1[:character] }, "Q"
  end
end
