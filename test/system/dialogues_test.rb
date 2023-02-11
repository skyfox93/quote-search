require "application_system_test_case"

class DialoguesTest < ApplicationSystemTestCase
  setup do
    @dialogue = dialogues(:one)
  end

  test "visiting the index" do
    visit dialogues_url
    assert_selector "h1", text: "Dialogues"
  end

  test "should create dialogue" do
    visit dialogues_url
    click_on "New dialogue"

    fill_in "Character", with: @dialogue.character
    fill_in "Episode", with: @dialogue.episode
    fill_in "Line", with: @dialogue.line
    fill_in "Series", with: @dialogue.series
    click_on "Create Dialogue"

    assert_text "Dialogue was successfully created"
    click_on "Back"
  end

  test "should update Dialogue" do
    visit dialogue_url(@dialogue)
    click_on "Edit this dialogue", match: :first

    fill_in "Character", with: @dialogue.character
    fill_in "Episode", with: @dialogue.episode
    fill_in "Line", with: @dialogue.line
    fill_in "Series", with: @dialogue.series
    click_on "Update Dialogue"

    assert_text "Dialogue was successfully updated"
    click_on "Back"
  end

  test "should destroy Dialogue" do
    visit dialogue_url(@dialogue)
    click_on "Destroy this dialogue", match: :first

    assert_text "Dialogue was successfully destroyed"
  end
end
