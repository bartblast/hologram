defmodule HologramFeatureTests.Rendering.PropValidationPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.PropValidationComponent

  route "/rendering/prop-validation"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, props: nil)
  end

  # The component is rendered through a spread, which is a usage the compiler can't decide - it can't
  # know which keys the map holds. That is what leaves the check to the client renderer, and it's the
  # only way to exercise it: a usage written out in full would fail this app's own build.
  def template do
    ~HOLO"""
    {%if @props}
      <PropValidationComponent ...{@props} />
    {/if}
    <p>
      <button $click="render_valid">Render valid</button>
      <button $click="render_without_required_prop">Render without required prop</button>
      <button $click="render_with_invalid_value">Render with invalid value</button>
    </p>
    """
  end

  def action(:render_valid, _params, component) do
    put_state(component, props: %{label: "my_label", size: :small})
  end

  def action(:render_without_required_prop, _params, component) do
    put_state(component, props: %{size: :small})
  end

  def action(:render_with_invalid_value, _params, component) do
    put_state(component, props: %{label: "my_label", size: :huge})
  end
end
