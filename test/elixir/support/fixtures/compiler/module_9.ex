# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module9 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-module9"

  layout Hologram.Test.Fixtures.Compiler.Module10

  def template do
    ~HOLO"""
    Module9 template
    """
  end

  def action(:action_9a, params, component) do
    fun_9a(params.my_key, component.state -- [1])
  end

  def fun_9a(map, key), do: Map.get(map, key)
end
