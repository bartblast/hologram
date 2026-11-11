defmodule HologramFeatureTests.Refs.Page2 do
  use Hologram.Page
  use Hologram.JS

  alias HologramFeatureTests.Components.Refs.Field

  route "/refs/2"

  layout HologramFeatureTests.Components.RefsLayout

  state :details?, :boolean, default: false
  state :field_ref, :any, default: {:field, 7}
  state :result, :any, default: nil
  state :swapped?, :boolean, default: false

  def template do
    ~HOLO"""
    <Field field_ref={@field_ref} />
    {%if @details?}<p $ref="details">Details text</p>{/if}
    <p $ref="note">Page 2 note</p>
    {%if @swapped?}<p $ref="swap">Second element</p>{%else}<p $ref="swap">First element</p>{/if}
    <p>
      <button $click="read_field">Read field</button>
      <button $click="read_layout_header">Read layout header</button>
      <button $click="read_note">Read note</button>
      <button $click="read_swapped_element">Read swapped element</button>
      <button $click="show_details">Show details</button>
      <button $click="toggle_swap">Toggle swap</button>
    </p>
    <p>Result: <strong id="page_2_result">{@result}</strong></p>
    """
  end

  def action(:read_details, _params, component) do
    text =
      :details
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "details: #{text}")
  end

  def action(:read_field, _params, component) do
    id =
      component.state.field_ref
      |> JS.element()
      |> JS.get(:id)

    put_state(component, :result, "field: #{id}")
  end

  def action(:read_layout_header, _params, component) do
    text =
      :layout_header
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "layout header: #{text}")
  end

  def action(:read_note, _params, component) do
    text =
      :note
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "note: #{text}")
  end

  def action(:read_swapped_element, _params, component) do
    text =
      :swap
      |> JS.element()
      |> JS.get(:textContent)

    put_state(component, :result, "swapped element: #{text}")
  end

  # The element this state change renders is on the page only once the action returns, so the
  # chained action looks it up.
  def action(:show_details, _params, component) do
    component
    |> put_state(:details?, true)
    |> put_action(:read_details)
  end

  def action(:toggle_swap, _params, component) do
    put_state(component, :swapped?, !component.state.swapped?)
  end
end
