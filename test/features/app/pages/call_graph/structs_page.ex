defmodule HologramFeatureTests.CallGraph.StructsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.StructFixture

  route "/structs"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="create_with_custom_values"> Create with custom values </button>
      <button $click="create_with_defaults"> Create with defaults </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:create_with_custom_values, _params, component) do
    my_struct = %StructFixture{name: "custom", value: 42}

    put_state(component, :result, {my_struct.name, my_struct.value})
  end

  def action(:create_with_defaults, _params, component) do
    my_struct = %StructFixture{}

    put_state(component, :result, {my_struct.name, my_struct.value})
  end
end
