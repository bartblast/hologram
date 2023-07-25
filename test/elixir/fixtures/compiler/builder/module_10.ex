# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Builder.Module10 do
  use Hologram.Layout

  def template do
    ~H"""
    Module10 template
    """
  end

  def action(:action_10a, params, state) do
    fun_10a(params, state)
  end

  def fun_10a(params, state), do: {params, state}
end
