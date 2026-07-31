defmodule HologramFeatureTests.ErrorOverlayPage do
  use Hologram.Page

  @dialyzer {:no_return, action: 3}

  route "/error-overlay"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <strong>Scenarios</strong>
      <button $click="raise_error"> Raise error </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:raise_error, _params, _component) do
    raise "overlaid error"
  end
end
