# The scenarios on this page verify that reflection functions ship for the modules server-executed
# code puts into state, when client code calls them on a module it reads from state rather than
# names. Client-reachable code on this page (template, actions) must not name the fixtures,
# otherwise the calls reach the reflection functions through ordinary edges and the scenarios
# silently stop testing which reflection functions the page can call.
defmodule HologramFeatureTests.CallGraph.DynamicReflectionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ReflectionFixture
  alias HologramFeatureTests.StructFixture1

  route "/call-graph/dynamic-reflection"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      result: nil,
      schema_module: ReflectionFixture,
      struct_module: StructFixture1
    )
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="build_with_struct"> Build with struct/2 </button>
      <button $click="build_with_struct_bang"> Build with struct!/2 </button>
      <button $click="build_with_dot"> Build with a dot </button>
      <button $click="read_changeset"> Read __changeset__/0 </button>
      <button $click="read_schema_fields"> Read __schema__/1 </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:build_with_dot, _params, component) do
    struct_module = component.state.struct_module
    my_struct = struct_module.__struct__

    put_state(component, :result, {my_struct.name, my_struct.value})
  end

  def action(:build_with_struct, _params, component) do
    my_struct = struct(component.state.struct_module)

    put_state(component, :result, {my_struct.name, my_struct.value})
  end

  def action(:build_with_struct_bang, _params, component) do
    my_struct = struct!(component.state.struct_module, name: "custom", value: 42)

    put_state(component, :result, {my_struct.name, my_struct.value})
  end

  def action(:read_changeset, _params, component) do
    schema_module = component.state.schema_module

    put_state(component, :result, schema_module.__changeset__())
  end

  def action(:read_schema_fields, _params, component) do
    schema_module = component.state.schema_module

    put_state(component, :result, schema_module.__schema__(:fields))
  end
end
