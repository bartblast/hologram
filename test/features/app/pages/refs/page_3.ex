defmodule HologramFeatureTests.Refs.Page3 do
  use Hologram.Page
  use Hologram.JS

  alias HologramFeatureTests.Components.Refs.FirstParagraph
  alias HologramFeatureTests.Components.Refs.SecondParagraph

  route "/refs/3"

  layout HologramFeatureTests.Components.RefsLayout

  state :late?, :boolean, default: false
  state :second_ref, :any, default: :second_paragraph
  state :shown?, :boolean, default: false

  def template do
    ~HOLO"""
    <input type="text" $ref="search" />
    {%if @shown?}<p $ref="hidden">Hidden</p>{/if}
    {%if @late?}<p $ref="late">Late</p>{/if}
    <FirstParagraph paragraph_ref={:first_paragraph} />
    <SecondParagraph paragraph_ref={@second_ref} />
    <p>
      <button $click="clash_refs">Clash refs</button>
      <button $click="read_hidden">Read hidden</button>
      <button $click="read_misspelled_ref">Read misspelled ref</button>
      <button $click="show_and_read_late">Show and read late</button>
    </p>
    """
  end

  def action(:clash_refs, _params, component) do
    put_state(component, :second_ref, :first_paragraph)
  end

  def action(:read_hidden, _params, component) do
    JS.element(:hidden)
    component
  end

  def action(:read_misspelled_ref, _params, component) do
    JS.element(:serch)
    component
  end

  # The element this state change renders is on the page only once the action returns.
  def action(:show_and_read_late, _params, component) do
    new_component = put_state(component, :late?, true)
    JS.element(:late)

    new_component
  end
end
