require "test_helper"

class ScriptHelperTest < ActionView::TestCase
  include ScriptHelper

  test "escapes transcript text, including HTML-looking content" do
    lines = ScriptText.lines("Q: <script>alert(1)</script> (snaps <b>fingers</b>)\n<img src=x onerror=alert(1)>")
    html = script_lines(lines)

    assert_not_includes html, "<script>"
    assert_not_includes html, "<img"
    assert_not_includes html, "<b>"
    assert_includes html, "&lt;script&gt;alert"
    assert_includes html, "&lt;img src=x onerror=alert"
  end

  test "marks speakers, inline directions and search terms" do
    html = script_lines(ScriptText.lines("PICARD: Engage the Romulan ship. (he sits)"), terms: %w[romulan])

    assert_includes html, %(<span class="speaker">PICARD</span>)
    assert_includes html, %(<mark>Romulan</mark>)
    assert_includes html, %(<span class="direction">(he sits)</span>)
  end

  test "terms in the text can't inject markup" do
    html = mark_terms(%(a <b>"romulan"</b>), ScriptText.term_pattern(%w[romulan]))
    assert_equal %(a &lt;b&gt;&quot;<mark>romulan</mark>&quot;&lt;/b&gt;), html
  end

  test "highlights a range of lines and anchors the first" do
    lines = ScriptText.lines("DATA: one\nDATA: two\nDATA: three\nDATA: four")
    html = script_lines(lines, highlight: 1..2)

    assert_equal 2, html.scan("line--match").size
    assert_equal 1, html.scan(%(id="match")).size
    assert_match(/id="match"[^>]*>.*two/m, html.to_s[/<p[^>]*id="match".*?<\/p>/m])
  end

  test "chunk_line_range maps excerpt lines in a chunk back onto the episode" do
    text = "HEADER\nA: one\nB: two\nC: three\nD: four\n"
    chunk = EpisodeChunk.new(content: "B: two\nC: three\nD: four")

    assert_equal 3...5, chunk_line_range(text, chunk, 1, 2)
    assert_nil chunk_line_range(text, EpisodeChunk.new(content: "not in the text"), 0, 1)
  end
end
