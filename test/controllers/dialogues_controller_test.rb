require "test_helper"

class DialoguesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dialogue = dialogues(:one)
  end

  test "should get index" do
    get dialogues_url
    assert_response :success
  end

  test "should get new" do
    get new_dialogue_url
    assert_response :success
  end

  test "should create dialogue" do
    assert_difference("Dialogue.count") do
      post dialogues_url, params: { dialogue: { character: @dialogue.character, episode: @dialogue.episode, line: @dialogue.line, series: @dialogue.series } }
    end

    assert_redirected_to dialogue_url(Dialogue.last)
  end

  test "should show dialogue" do
    get dialogue_url(@dialogue)
    assert_response :success
  end

  test "should get edit" do
    get edit_dialogue_url(@dialogue)
    assert_response :success
  end

  test "should update dialogue" do
    patch dialogue_url(@dialogue), params: { dialogue: { character: @dialogue.character, episode: @dialogue.episode, line: @dialogue.line, series: @dialogue.series } }
    assert_redirected_to dialogue_url(@dialogue)
  end

  test "should destroy dialogue" do
    assert_difference("Dialogue.count", -1) do
      delete dialogue_url(@dialogue)
    end

    assert_redirected_to dialogues_url
  end
end
