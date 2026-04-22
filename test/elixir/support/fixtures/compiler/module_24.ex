# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module24 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-module24"

  layout Hologram.Test.Fixtures.Compiler.Module10

  def template do
    ~HOLO"""
    Module24 template
    """
  end

  def action(:action_24a, params, component) do
    result = :erlang.bnot(params.value)
    put_state(component, :result, result)
  end
end
