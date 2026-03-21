# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module25 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-module25"

  layout Hologram.Test.Fixtures.Compiler.Module10

  def template do
    ~HOLO"""
    Module25 template
    """
  end

  def action(:action_25a, _params, component) do
    component
  end
end
