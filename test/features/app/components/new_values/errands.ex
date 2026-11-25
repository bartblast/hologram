defmodule HologramFeatureTests.Components.NewValues.Errands do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Errand
  alias HologramFeatureTests.Entities.Squad

  derived :errands, [Errand], &errands_query/0

  # The browser can answer for a move only to a squad it holds, so the page lists them, as a picker
  # of where to move an errand would.
  derived :squads, [Squad], &squads_query/0

  def template do
    ~HOLO"""
    <ul id="errands">
      {%for errand <- @errands}
        <li>{errand.title} {errand.status} archived={errand.archived} squad={errand.squad_id}</li>
      {/for}
    </ul>
    <ul id="squads">
      {%for squad <- @squads}
        <li>{squad.name}</li>
      {/for}
    </ul>
    """
  end

  defp errands_query do
    sort(Errand, title)
  end

  defp squads_query do
    sort(Squad, name)
  end
end
