defmodule HologramFeatureTests.Components.CompoundKey.Reactions do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Reaction

  # The reactions reach this list through a registered query the client evaluates against its
  # own database, so a row an action wrote is on screen before the server has judged it - and
  # gone again once the server refuses its batch.
  derived :reactions, [Reaction], &reactions_query/0

  def template do
    ~HOLO"""
    <ul id="reactions">
      {%for reaction <- @reactions}
        <li>{reaction.reactor} {reaction.emoji}</li>
      {/for}
    </ul>
    """
  end

  defp reactions_query do
    sort(Reaction, emoji)
  end
end
