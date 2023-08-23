# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module10 do
  use Hologram.Layout

  def template do
    ~H"""
    Module10 template
    """
  end

  def action(:action_10a, params, client) do
    fun_10a(params, client)
  end

  def fun_10a(params, state), do: {params, state}
end
