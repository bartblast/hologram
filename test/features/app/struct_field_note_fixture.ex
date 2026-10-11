# Held in the note field of the struct the struct field page builds on the server, and referenced by
# no other app code: the page puts only the title field into the state. So the String.Chars
# implementation must be in neither the runtime nor a page bundle, only in a chunk, and the page
# must load none of the struct's chunks. Referencing the struct anywhere else would silently stop
# testing that.
defmodule HologramFeatureTests.StructFieldNoteFixture do
  defstruct text: "note"
end

defimpl String.Chars, for: HologramFeatureTests.StructFieldNoteFixture do
  def to_string(data) do
    "note(#{data.text})"
  end
end
