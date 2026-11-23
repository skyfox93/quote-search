import { Controller } from "@hotwired/stimulus"

// Runs the SQL agent for a question and shows each step as it arrives.
// The server streams complete <turbo-stream> elements (rendered and escaped
// by Rails partials); each one is handed to Turbo as soon as it is complete.
export default class extends Controller {
  static targets = ["status", "statusText"]
  static values = { url: String }

  connect() {
    this.abort = new AbortController()
    this.run()
  }

  disconnect() {
    this.abort.abort()
  }

  async run() {
    let steps = 0
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/html" }, signal: this.abort.signal })
      if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`)

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ""
      const closing = "</turbo-stream>"
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        let end
        while ((end = buffer.indexOf(closing)) >= 0) {
          window.Turbo.renderStreamMessage(buffer.slice(0, end + closing.length))
          buffer = buffer.slice(end + closing.length)
          steps += 1
          this.statusTextTarget.textContent = "Reading the results and deciding what to do next…"
        }
      }
      if (steps === 0) throw new Error("empty response")
    } catch (error) {
      if (error.name === "AbortError") return
      this.showError()
    } finally {
      if (!this.abort.signal.aborted) this.statusTarget.remove()
    }
  }

  showError() {
    const item = document.createElement("li")
    item.className = "agent-step agent-step--error"
    const notice = document.createElement("div")
    notice.className = "notice notice--error"
    notice.textContent = "The agent stopped unexpectedly. Please try again."
    item.append(notice)
    this.element.querySelector("#agent-steps")?.append(item)
  }
}
