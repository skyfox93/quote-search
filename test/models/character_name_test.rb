require "test_helper"

class CharacterNameTest < ActiveSupport::TestCase
  def std(raw, series: nil) = CharacterName.standardize(raw, series: series)

  test "moves delivery tags out of the name" do
    assert_equal ["PICARD", "OC"], std("PICARD [OC]").to_h.values
    assert_equal ["DUKAT", "on monitor"], std("DUKAT [on monitor]").to_h.values
    assert_equal ["TANIS", "telepathically"], std("TANIS (telepathically)").to_h.values
    assert_equal ["ODO", "OC"], std("ODO {OC]").to_h.values
    assert_equal ["THARN", "on viewscreen"], std("THARN [on viewscreen").to_h.values
  end

  test "cleans punctuation and spacing, and spaces out numbers" do
    assert_equal "PARIS", std("PARIS:").name
    assert_equal "T'GRETH", std("T'GRETH?").name
    assert_equal "EMH 2", std("EMH2").name
    assert_equal "WEYOUN 7", std("WEYOUN7 [on monitor]").name
    assert_equal "RIKER 2", std("RIKER 2").name, "numbered people stay distinct"
    assert_equal "DR. CRUSHER", std("DR. CRUSHER").name
    assert_equal "Q", std("Q").name
  end

  test "finds the speaker when a previous line ran into the name" do
    assert_equal "KES", std("KES: No. (She looks up at Neelix.)KES").name
    assert_equal "KIM", std("SEVEN: Proceed.KIM").name
    assert_equal "PARIS", std("TORRES: Mop, mop, don't stopPARIS").name
    assert_equal "SEVEN", std("PADD and lowers the forcefield.) <br>SEVEN").name
    assert_equal ["JANEWAY", "OC"], std("JANEWAY: Janeway to Harren. [Escape pod]JANEWAY [OC]").to_h.values
  end

  test "uses the prefix when a colon inside the line split it early" do
    assert_equal "DATA", std("DATA: Computer").name
    assert_equal "CHAKOTAY", std("CHAKOTAY: A long one. A Cave Beyond Logic").name
  end

  test "stage directions with no speaker become SCENE" do
    assert_equal "SCENE", std("O'Brien leave. We skip a couple of minutes. 3:44 3").name
  end

  test "fixes misspellings only within their series" do
    assert_equal "CHAKOTAY", std("CHAOTAY", series: "VOY").name
    assert_equal "WORF", std("WORD", series: "TNG").name
    assert_equal "WORD", std("WORD", series: "DS9").name
  end
end
