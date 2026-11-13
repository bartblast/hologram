defmodule HologramFeatureTests.Rendering.UndefinedVarPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.UndefinedVarComponent

  route "/rendering/undefined-var"

  layout HologramFeatureTests.Components.DefaultLayout

  state :show?, :boolean

  def init(_params, component, _server) do
    put_state(component, show?: false)
  end

  # The component is left out of the server render, so the page loads and the first render of the
  # component's template is the client's.
  def template do
    ~HOLO"""
    {%if @show?}
      <UndefinedVarComponent label="my_label" />
    {/if}
    <p>
      <button $click="show">Show</button>
    </p>
    """
  end

  def action(:show, _params, component) do
    put_state(component, show?: true)
  end
end
