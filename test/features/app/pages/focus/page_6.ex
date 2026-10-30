defmodule HologramFeatureTests.Focus.Page6 do
  use Hologram.Page

  route "/focus/6/:id"

  param :id, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  def init(params, component, _server) do
    put_state(component, :id, params.id)
  end

  # The field holds the same place in the template for every id, so a navigation from one id to
  # the next keeps its DOM node. A page arrival that declares no focus has to take focus off it
  # anyway, the way a document load starts with nothing focused.
  def template do
    ~HOLO"""
    <h1>Page 6 title {@id}</h1>
    <p>
      <input type="text" id="page_6_kept" />
      <button id="page_6_next" $click="next">Next</button>
    </p>
    """
  end

  def action(:next, _params, component) do
    put_page(component, __MODULE__, id: component.state.id + 1)
  end
end
