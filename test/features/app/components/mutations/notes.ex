defmodule HologramFeatureTests.Components.Mutations.Notes do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Entities.Note

  # The notes reach this list through the ordinary read path - a registered query filled by the
  # sync stream - so a note written by a batch POSTed from the page appears here without the page
  # being fetched again. That is the whole claim the scenarios check.
  prop :notes, [Note], from_query: &notes_query/0

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
    order_by(Note, :body)
  end
end
