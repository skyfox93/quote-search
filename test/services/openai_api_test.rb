require "test_helper"

class OpenaiApiTest < ActiveSupport::TestCase
  # Stands in for Net::HTTPResponse#read_body, delivering the body in pieces.
  FakeResponse = Struct.new(:pieces) do
    def read_body(&block) = pieces.each(&block)
  end

  test "parses server-sent events split across network reads" do
    body = [
      %(data: {"choices":[{"delta":{"content":"Dar"}}]}\n\nda),
      %(ta: {"choices":[{"delta":{"content":"mok"}}]}\n\n: keep-alive\n\n),
      %(data: [DONE]\n\n)
    ]
    payloads = []
    OpenaiApi.send(:each_sse_data, FakeResponse.new(body)) { payloads << JSON.parse(_1).dig("choices", 0, "delta", "content") }

    assert_equal %w[Dar mok], payloads
  end

  test "reads the whole body even after [DONE]" do
    read = []
    body = [%(data: [DONE]\n\n), "trailing"]
    response = FakeResponse.new(body)
    response.define_singleton_method(:read_body) { |&blk| body.each { read << _1; blk.call(_1) } }

    OpenaiApi.send(:each_sse_data, response) { flunk "nothing to yield" }
    assert_equal body, read
  end
end
