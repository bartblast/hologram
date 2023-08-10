# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Builder.Module9 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Builder.Module10

  route "/my_path"

  def template do
    ~H"""
    Module9 template
    """
  end

  def action(:action_9a, params, state) do
    fun_9a(params.my_key, state + 1)
  end

  def fun_9a(map, key), do: Map.get(map, key)
end
