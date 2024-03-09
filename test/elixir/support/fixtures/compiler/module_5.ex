# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module5 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Module7

  route "/hologram-test-fixtures-compiler-module5"

  layout Hologram.Test.Fixtures.Compiler.Module6

  def template do
    ~H"""
    Module5 template
    """
  end

  def action(:action_5a, params, component) do
    Module7.my_fun_7a(params, component)
  end

  def action(:action_5b, _params, component) do
    component
    |> Enum.to_list()
    |> :erlang.hd()
  end

  def action(:action_5c, _params, _component) do
    Kernel.inspect(123)
  end
end
