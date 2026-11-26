defmodule HologramFeatureTests.ShortIds.Page2 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Notice

  route "/short-ids/2/:id"

  param :id, :id

  layout HologramFeatureTests.Components.DefaultLayout

  derived :notice, Notice, fn id ->
    Notice
    |> filter(id == ^id)
    |> one()
  end

  def template do
    ~HOLO"""
    <p>
      Id: <strong id="id"><code>{@id}</code></strong>
    </p>
    <p>
      Title: <strong id="title"><code>{%if @notice}{@notice.title}{%else}none{/if}</code></strong>
    </p>
    """
  end
end
