defmodule HologramFeatureTests.ShortIds.Page1 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.Entities.Notice
  alias HologramFeatureTests.ShortIds.Page2

  route "/short-ids/1"

  layout HologramFeatureTests.Components.DefaultLayout

  derived :notice, Notice, fn ->
    Notice
    |> filter(title == "made_on_server")
    |> one()
  end

  # The link's path is built from the server's notice, so it carries the id the server gave it.
  def template do
    ~HOLO"""
    <p>
      <button $click="create_notice"> Create a notice </button>
    </p>
    {%if @notice}
      <p>
        <Link to={Page2, id: @notice.id}>Notice link</Link>
      </p>
    {/if}
    """
  end

  # The notice is created in the BROWSER, so its id is one the browser made, and the page it goes
  # to reads it from the browser's own database before the server has seen it.
  def action(:create_notice, _params, component) do
    {:ok, notice} =
      %{title: "made_in_browser"}
      |> Notice.new()
      |> DB.create()

    put_page(component, Page2, id: notice.id)
  end
end
