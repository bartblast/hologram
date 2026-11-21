defmodule HologramFeatureTests.SplitUpdatePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Docket
  alias HologramFeatureTests.Entities.Sticker

  route "/split-update"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="close_and_stick"> Close and stick </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # The write runs in the BROWSER: one update/1 call putting a value and adding an edge, which the
  # batch carries as an entry for each.
  def action(:close_and_stick, _params, component) do
    sticker =
      Sticker
      |> one()
      |> DB.read()

    Docket
    |> one()
    |> DB.read()
    |> put_attribute(:status, "closed")
    |> add_relationship(:stickers, sticker.id)
    |> DB.update!()

    put_state(component, :result, "closed_and_stuck")
  end
end
