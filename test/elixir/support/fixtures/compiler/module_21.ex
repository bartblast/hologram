# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module21 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Module20

  route "/hologram-test-fixtures-compiler-module21"

  layout Hologram.Test.Fixtures.Compiler.Module6

  def template do
    ~HOLO"""
    Module21 template
    """
  end

  def action(:action_21a, _params, _component) do
    Module20.my_fun()
  end
end
