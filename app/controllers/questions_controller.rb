# "Ask a question": an AI agent answers by querying the database (SearchAgent).
class QuestionsController < ApplicationController
  include ActionController::Live

  # GET /ask?q=...  Renders at once; the page then fetches #stream.
  def index
    @question = question_param
  end

  # GET /ask/stream?q=...
  # Streams the agent's steps as they happen, each as a <turbo-stream> element
  # (rendered from the same partials the landing page uses) that the page's
  # agent controller hands to Turbo.
  def stream
    question = question_param
    return head(:bad_request) if question.blank?

    response.headers["Content-Type"] = "text/html; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Last-Modified"] = Time.now.httpdate # stops Rack::ETag buffering the stream

    unless OpenaiApi.configured?
      write_event(SearchAgent::Event.error("The agent needs an OpenAI API key (OPENAI_API_KEY)."))
      return
    end

    SearchAgent.new(question).run { |event| write_event(event) }
  rescue ActionController::Live::ClientDisconnected, IOError
    nil # the browser left; the agent run was cut short
  ensure
    response.stream.close
  end

  private

  def question_param
    params[:q].to_s.squish.truncate(SearchAgent::MAX_QUESTION_LENGTH, omission: "")
  end

  def write_event(event)
    html = ApplicationController.render(partial: "questions/event", locals: { event: event })
    response.stream.write(%(<turbo-stream action="append" target="agent-steps"><template>#{html}</template></turbo-stream>\n))
  end
end
