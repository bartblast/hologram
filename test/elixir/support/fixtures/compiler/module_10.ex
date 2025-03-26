# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module10 do
  use Hologram.Component

  def template do
    ~HOLO"""
    Module10 template
    """
  end

  def action(:action_10a, params, component) do
    fun_10a(params, component)
  end

  def fun_10a(params, state), do: {params, state}
end
