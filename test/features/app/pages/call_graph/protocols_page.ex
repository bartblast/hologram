defmodule HologramFeatureTests.CallGraph.ProtocolsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ProtocolFixture
  alias HologramFeatureTests.StructFixture

  route "/call-graph/protocols"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="dispatch_for_atom"> Dispatch for atom </button>
      <button $click="dispatch_for_struct"> Dispatch for struct </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dispatch_for_atom, _params, component) do
    result = ProtocolFixture.format(:hello)

    put_state(component, :result, result)
  end

  def action(:dispatch_for_struct, _params, component) do
    result = ProtocolFixture.format(%StructFixture{name: "test", value: 7})

    put_state(component, :result, result)
  end
end
