require "test_helper"

class ScriptTextTest < ActiveSupport::TestCase
  RAW = <<~TEXT.chomp
    The Next Generation Transcripts - The Mind's Eye    The Mind's Eye Stardate: 44885.5 Original Airdate: 27 May, 1991         Personal log, Chief Engineer Geordi La Forge.  [Shuttlecraft]  (Geordi has his feet up)
    LAFORGE: How about some different music, Computer.
    COMPUTER: Risa is clear.

    (A Romulan ship decloaks)
    [Bridge]
    PICARD [OC]: Report.
    DATA: Sir, I am.<br>
    TROI: It'll take time.         <Back to the episode listing Star Trek ® and related marks are trademarks of CBS Studios Inc.
  TEXT

  test "parses speakers, directions and locations, keeping raw line indexes" do
    lines = ScriptText.lines(RAW)

    assert_equal [0, 1, 2, 4, 5, 6, 7, 8], lines.map(&:index)
    assert_equal ["LAFORGE", "How about some different music, Computer."], [lines[1].speaker, lines[1].text]
    assert lines[3].direction?
    assert lines[4].location?
    assert_equal "PICARD [OC]", lines[5].speaker
  end

  test "strips the transcript site's header, footer and stray <br>" do
    lines = ScriptText.lines(RAW)

    assert lines.first.text.start_with?("Personal log, Chief Engineer")
    assert_equal "Sir, I am.", lines[6].text
    assert_equal "It'll take time.", lines.last.text
  end

  test "terms drop stopwords, series names and short words" do
    assert_equal %w[geordi assassin], ScriptText.terms("in what episode of TNG does Geordi become an assassin")
    assert_equal %w[geordi assassin romulan], ScriptText.terms("Geordi, assassin", "in TNG a Romulan")
  end

  test "term pattern matches word starts and escapes regex characters" do
    pattern = ScriptText.term_pattern(["assassin", "c++"])
    assert_match pattern, "an assassination"
    assert_no_match pattern, "classassin"
    assert_nil ScriptText.term_pattern([])
  end

  test "terms are cut to a rough stem so other forms of the word match" do
    assert_equal %w[data learn joke], ScriptText.terms("Data learning jokes")
    assert_equal %w[picard live glass bus], ScriptText.terms("Picard lives glasses bus")
    assert_match ScriptText.term_pattern(ScriptText.terms("jokes")), "a joke"
    assert_match ScriptText.term_pattern(ScriptText.terms("learning")), "he learned"
  end

  test "excerpt picks the window with the most distinct terms" do
    lines = ScriptText.lines((1..20).map { "DATA: line #{_1}" }.join("\n") + "\nPICARD: the Romulan assassin\nRIKER: a Romulan")
    excerpt = ScriptText.excerpt(lines, %w[romulan assassin], size: 3)

    assert_equal 3, excerpt.size
    assert_includes excerpt.map(&:text), "the Romulan assassin"
  end

  test "excerpt falls back to the first lines" do
    lines = ScriptText.lines((1..10).map { "DATA: line #{_1}" }.join("\n"))
    assert_equal lines.first(4), ScriptText.excerpt(lines, [], size: 4)
    assert_equal lines.first(4), ScriptText.excerpt(lines, %w[nomatch], size: 4)
  end
end
