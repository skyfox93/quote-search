module HomeHelper
  # Escapes a ts_headline-style string and turns its ⟦ ⟧ markers into <mark>.
  # safe_join escapes the plain parts.
  def headline_marks(text)
    safe_join(text.to_s.split(/(⟦[^⟧]*⟧)/).map do |part|
      part.start_with?("⟦") ? content_tag(:mark, part.delete("⟦⟧")) : part
    end)
  end
end
