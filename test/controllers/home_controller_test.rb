require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "landing page explains the three levels, each with its live demo" do
    get root_path

    assert_response :success
    assert_select "#level-1 .level__title", /Keyword search/
    assert_select "#level-2 .level__title", /RAG/
    assert_select "#level-3 .level__title", /agent/
    assert_select "turbo-frame[data-turbo-action]", false, "demo searches stay on the homepage"
    assert_select "[autofocus]", false

    assert_select "#level-1 .example .compare__item--win .compare__num", "295"
    assert_select "#level-1 turbo-frame#demo-keyword form[action=?] input[name=query]", dialogues_path
    assert_select "#level-1 .how-it-works", "How it works"
    assert_select "#level-2 .example .mini-result", 3
    assert_select "#level-2 turbo-frame#demo-rag form[action=?] input[name=query]", episode_texts_path
    assert_select "#level-3 .example .agent-step--sql", 2
    assert_select "#level-3 turbo-frame#demo-agent form[action=?] input[name=q]", ask_path
  end

  test "headline_marks escapes text and marks the matches" do
    helper = Class.new { include ActionView::Helpers, HomeHelper }.new
    assert_equal "You will be <mark>assimilated</mark> &lt;b&gt;", helper.headline_marks("You will be ⟦assimilated⟧ <b>")
  end
end
