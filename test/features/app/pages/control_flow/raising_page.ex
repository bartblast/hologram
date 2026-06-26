defmodule HologramFeatureTests.ControlFlow.RaisingPage do
  use Hologram.Page

  route "/control-flow/raising"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>
      <button $click="exit_reason"> Exit </button>
      <button $click="raise_error"> Raise </button>
      <button $click="throw_value"> Throw </button>
    </p>
    """
  end

  def action(:exit_reason, _params, _component) do
    exit("my reason")
  end

  def action(:raise_error, _params, _component) do
    raise RuntimeError, "my message"
  end

  def action(:throw_value, _params, _component) do
    throw("my value")
  end
end
