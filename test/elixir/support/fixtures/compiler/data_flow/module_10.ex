# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module10 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module11
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct4
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct6

  route "/hologram-test-fixtures-compiler-dataflow-module10"

  layout Hologram.Test.Fixtures.LayoutFixture

  # Struct1 and Struct6 are built and dropped on the server (no other fixture hands Struct6 to the
  # client), Struct2 and the Module11 component reach the state, Struct3 stays in the session.
  def init(_params, component, server) do
    new_component =
      put_state(component,
        label: describe(%Struct6{field: :label}),
        text: describe(%Struct1{field: :transient}),
        struct: %Struct2{},
        component: Module11
      )

    {new_component, put_session(server, :struct, %Struct3{})}
  end

  def template do
    ~HOLO""
  end

  # Struct4 reaches the client in the params of the action the command puts.
  def command(:load, _params, server) do
    put_action(server, :loaded, struct: %Struct4{})
  end

  defp describe(struct), do: "#{struct.field}"
end
