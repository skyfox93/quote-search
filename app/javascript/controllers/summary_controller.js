import { Controller } from "@hotwired/stimulus"

// Streams the AI summary of a search into the page as it's written, with a
// small subset of markdown: paragraphs, "-" / "1." lists, **bold**, *italic*
// and `code`. The answer is untrusted model output, so it is never parsed as
// HTML: every element is built with the DOM API and all text goes in as text
// nodes. "[2]" citations become links to the results.
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

  // Blocks are separated by blank lines; a block whose lines all start with
  // "- ", "* " or "1. " is a list. While streaming, an unfinished **bold**
  // shows as typed until its closing marker arrives.
  render(text) {
    const blocks = text.trim().split(/\n\s*\n/).filter((block) => block.trim())
    const nodes = blocks.map((block) => {
      const lines = block.split("\n").filter((line) => line.trim())
      const bullet = /^\s*(?:[-*•]|\d+[.)])\s+/
      if (lines.every((line) => bullet.test(line))) {
        const list = document.createElement(/^\s*\d/.test(lines[0]) ? "ol" : "ul")
        for (const line of lines) {
          const item = document.createElement("li")
          item.append(...this.inline(line.replace(bullet, "")))
          list.append(item)
        }
        return list
      }
      const paragraph = document.createElement("p")
      paragraph.append(...this.inline(lines.join(" ").replace(/^#+\s+/, "")))
      return paragraph
    })
    this.outputTarget.replaceChildren(...(nodes.length ? nodes : [document.createElement("p")]))
  }

  // **bold**, *italic* / _italic_, `code` and [n] citations, as DOM nodes.
  inline(text) {
    const pattern = /(\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`|\*[^*\s][^*\n]*\*|(?<!\w)_[^_\s][^_\n]*_(?!\w)|\[\d+\])/
    return text.split(pattern).filter(Boolean).map((part) => {
      const number = Number(part.match(/^\[(\d+)\]$/)?.[1])
      if (number >= 1 && number <= this.countValue) return this.citation(number)
      const styled = [[/^\*\*(.+)\*\*$/, "strong"], [/^__(.+)__$/, "strong"], [/^`(.+)`$/, "code"],
                      [/^\*(.+)\*$/, "em"], [/^_(.+)_$/, "em"]]
      for (const [regex, tag] of styled) {
        const match = part.match(regex)
        if (match) {
          const element = document.createElement(tag)
          element.append(...(tag === "code" ? [document.createTextNode(match[1])] : this.inline(match[1])))
          return element
        }
      }
      return document.createTextNode(part)
    })
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
    message.textContent = "The AI summary isn't available right now, but the matching scenes are below."
    this.outputTarget.replaceChildren(message)
  }
}
