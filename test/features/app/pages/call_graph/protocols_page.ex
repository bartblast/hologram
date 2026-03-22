defmodule HologramFeatureTests.CallGraph.ProtocolsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ProtocolFixture
  alias HologramFeatureTests.StructFixture1
  alias HologramFeatureTests.StructFixture2

  route "/call-graph/protocols"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="dispatch_enumerable_for_list"> Dispatch Enumerable for list </button>
      <button $click="dispatch_enumerable_for_struct"> Dispatch Enumerable for struct </button>
      <button $click="dispatch_custom_for_atom"> Dispatch for atom </button>
      <button $click="dispatch_custom_for_struct"> Dispatch for struct </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dispatch_enumerable_for_list, _params, component) do
    result = Enum.map([10, 20, 30], fn x -> x * 3 end)

    put_state(component, :result, result)
  end

  def action(:dispatch_enumerable_for_struct, _params, component) do
    enumerable = %StructFixture2{items: [10, 20, 30]}
    result = Enum.map(enumerable, fn x -> x * 2 end)

    put_state(component, :result, result)
  end

  def action(:dispatch_custom_for_atom, _params, component) do
    result = ProtocolFixture.format(:hello)

    put_state(component, :result, result)
  end

  def action(:dispatch_custom_for_struct, _params, component) do
    result = ProtocolFixture.format(%StructFixture1{name: "test", value: 7})

    put_state(component, :result, result)
  end
end
