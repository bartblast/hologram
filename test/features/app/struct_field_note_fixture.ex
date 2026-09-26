# Held in the note field of the struct the struct field page builds on the server, and referenced by
# no other app code: the page puts only the title field into the state, so the String.Chars
# implementation must reach no bundle. Referencing the struct anywhere else would silently stop
# testing that.
defmodule HologramFeatureTests.StructFieldNoteFixture do
  defstruct text: "note"
end

defimpl String.Chars, for: HologramFeatureTests.StructFieldNoteFixture do
  def to_string(data) do
    "note(#{data.text})"
  end
end
