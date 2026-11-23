import { Controller } from "@hotwired/stimulus"

// Streams the AI answer for a search into the page as it's written.
// The answer is untrusted model output: it is only ever inserted as text
// nodes, and "[2]" citations become links built with the DOM API.
export default class extends Controller {
  static targets = ["output"]
  static values = { url: String, count: Number }

  connect() {
    this.abort = new AbortController()
    this.load()
  }

  disconnect() {
    this.abort.abort()
  }

  async load() {
    let text = ""
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/plain" },
        signal: this.abort.signal
      })
      if (response.status === 204) return this.element.remove()
      if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`)

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      this.element.classList.add("is-streaming")
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        text += decoder.decode(value, { stream: true })
        this.render(text)
      }
      text += decoder.decode()
      if (!text.trim()) throw new Error("empty answer")
      this.render(text)
    } catch (error) {
      if (error.name === "AbortError") return
      this.fail(text)
    } finally {
      this.element.classList.remove("is-streaming")
      this.outputTarget.setAttribute("aria-busy", "false")
    }
  }

  render(text) {
    const paragraph = document.createElement("p")
    for (const part of text.split(/(\[\d+\])/)) {
      const number = Number(part.match(/^\[(\d+)\]$/)?.[1])
      if (number >= 1 && number <= this.countValue) {
        paragraph.append(this.citation(number))
      } else if (part) {
        paragraph.append(document.createTextNode(part))
      }
    }
    this.outputTarget.replaceChildren(paragraph)
  }

  citation(number) {
    const link = document.createElement("a")
    link.href = `#result-${number}`
    link.className = "cite"
    link.textContent = number
    link.setAttribute("aria-label", `Result ${number}`)
    link.addEventListener("click", (event) => {
      const target = document.getElementById(`result-${number}`)
      if (!target) return
      event.preventDefault()
      target.scrollIntoView({ behavior: "smooth", block: "start" })
      target.classList.remove("is-flashing")
      void target.offsetWidth // restart the animation
      target.classList.add("is-flashing")
    })
    return link
  }

  fail(partial) {
    if (partial.trim()) return this.render(partial)
    const message = document.createElement("p")
    message.className = "ai-answer__error"
    message.textContent = "The AI answer isn't available right now, but the matching scenes are below."
    this.outputTarget.replaceChildren(message)
  }
}
