defmodule HologramFeatureTests.TimeAttributePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.TimeAttribute.Shops
  alias HologramFeatureTests.Entities.Shop

  route "/time-attribute"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :add_shop_without_hours}> Add a shop with no hours </button>
      <button $click={action: :add_two_shops}> Add two shops at different times </button>
      <button $click={action: :refuse_late_shop}> Refuse a shop opening too late </button>
    </p>
    <Shops cid="shops" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:add_shop_without_hours, _params, component) do
    {:ok, _shop} =
      %{name: "anytime"}
      |> Shop.new()
      |> DB.create()

    put_state(component, :result, "created_anytime")
  end

  # The later shop is written FIRST, so the list can only come out in time order if the ordering
  # put it there - insertion order would read the other way round.
  def action(:add_two_shops, _params, component) do
    {:ok, _noon} =
      %{closes_at: ~T[20:00:00], name: "noon", opens_at: ~T[12:00:00]}
      |> Shop.new()
      |> DB.create()

    {:ok, _dawn} =
      %{closes_at: ~T[16:30:00], name: "dawn", opens_at: ~T[08:30:00]}
      |> Shop.new()
      |> DB.create()

    put_state(component, :result, "created_two")
  end

  # The bounds are baked into the bundle, so this refusal never leaves the browser - which it can
  # only do if Time.compare/2 transpiled.
  def action(:refuse_late_shop, _params, component) do
    {:error, %{opens_at: [{:max, max}]}} =
      %{name: "late", opens_at: ~T[21:00:00]}
      |> Shop.new()
      |> DB.create()

    put_state(component, :result, "refused_max_#{max.hour}")
  end
end
