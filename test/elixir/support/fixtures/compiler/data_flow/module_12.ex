# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module12 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct5

  route "/hologram-test-fixtures-compiler-dataflow-module12"

  layout Hologram.Test.Fixtures.LayoutFixture

  # A rescued exception can hold whatever init/3 reaches, so the rule before the analysis applies
  # from init/3: the Struct5 it names counts, though only its field reaches the state.
  def init(params, component, _server) do
    put_state(component, :field, build(params).field)
  rescue
    error -> put_state(component, :error, error)
  end

  def template do
    ~HOLO""
  end

  defp build(params), do: %Struct5{field: params[:field]}
end
