module HomeHelper
  # Escapes a ts_headline result and turns its ⟦ ⟧ markers into <mark>.
  def headline_marks(text)
    safe_join(text.to_s.split(/(⟦[^⟧]*⟧)/).map do |part|
      part.start_with?("⟦") ? content_tag(:mark, part.delete("⟦⟧")) : h(part)
    end)
  end

  # Escapes an AI answer and turns "[2]" citations into links to
  # "#<prefix>-2", for citations 1..max.
  def cited_answer(text, max:, prefix:)
    safe_join(text.to_s.split(/(\[\d+\])/).map do |part|
      n = part[/\A\[(\d+)\]\z/, 1].to_i
      if n.between?(1, max)
        link_to(n.to_s, "##{prefix}-#{n}", class: "cite", aria: { label: "Result #{n}" })
      else
        h(part)
      end
    end)
  end

  # The word forms a dictionary search matched, from ts_headline markers.
  def matched_forms(headlines)
    headlines.flat_map { _1.to_s.scan(/⟦([^⟧]*)⟧/).flatten }.map(&:downcase).uniq.sort
  end
end
