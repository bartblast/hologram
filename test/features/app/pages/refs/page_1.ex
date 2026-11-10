defmodule HologramFeatureTests.Refs.Page1 do
  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias HologramFeatureTests.Refs.Page2

  route "/refs/1"

  layout HologramFeatureTests.Components.RefsLayout

  state :items, :list, default: [%{id: 1}, %{id: 2}, %{id: 3}]
  state :result, :any, default: nil

  def template do
    ~HOLO"""
    <p>
      <input type="text" id="page_1_search" $ref="search" />
    </p>
    <ul>
      {%for item <- @items}
        <li $ref={:item, item.id}>Item {item.id}</li>
      {/for}
    </ul>
    <p>
      <button $click="focus_search">Focus search</button>
      <button $click="pass_native_value">Pass native value</button>
      <button $click="read_document">Read document</button>
      <button $click="read_item">Read item</button>
      <button $click="read_third_item">Read third item</button>
      <button $click="read_window">Read window</button>
    </p>
    <p>Result: <strong id="page_1_result">{@result}</strong></p>
    <p><Link to={Page2}>Go to page 2</Link></p>
    """
  end

  def action(:focus_search, _params, component) do
    :search
    |> JS.element()
    |> JS.call(:focus, [])

    component
  end

  def action(:pass_native_value, _params, component) do
    id =
      :search
      |> JS.element()
      |> JS.element()
      |> JS.get(:id)

    put_state(component, :result, "native value: #{id}")
  end

  def action(:read_document, _params, component) do
    tag_name =
      :document
      |> JS.element()
      |> JS.get(:documentElement)
      |> JS.get(:tagName)

    put_state(component, :result, "document: #{tag_name}")
  end

  def action(:read_item, _params, component) do
    text =
      {:item, 2}
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "item: #{text}")
  end

  def action(:read_third_item, _params, component) do
    text =
      {:item, 3}
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "third item: #{text}")
  end

  def action(:read_window, _params, component) do
    pathname =
      :window
      |> JS.element()
      |> JS.get(:location)
      |> JS.get(:pathname)

    put_state(component, :result, "window: #{pathname}")
  end
end
