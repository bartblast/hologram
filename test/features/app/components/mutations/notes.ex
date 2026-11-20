defmodule HologramFeatureTests.Components.Mutations.Notes do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Note

  # The notes reach this list through the ordinary read path - a derived query over the rows the
  # sync stream keeps current - so a note written by a batch POSTed from the page appears here without the page
  # being fetched again. That is the whole claim the scenarios check.
  derived :notes, [Note], &notes_query/0

  def template do
    ~HOLO"""
    <ul id="notes">
      {%for note <- @notes}
        <li>{note.body}</li>
      {/for}
    </ul>
    """
  end

  defp notes_query do
    sort(Note, body)
  end
end
