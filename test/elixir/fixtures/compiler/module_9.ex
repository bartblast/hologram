# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module9 do
  use Hologram.Page

  route "/module_9"

  layout Hologram.Test.Fixtures.Compiler.Module10

  def template do
    ~H"""
    Module9 template
    """
  end

  def action(:action_9a, params, client) do
    fun_9a(params.my_key, client + 1)
  end

  def fun_9a(map, key), do: Map.get(map, key)
end
