# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module19 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Module18

  route "/hologram-test-fixtures-compiler-module19"

  layout Hologram.Test.Fixtures.Compiler.Module6

  def template do
    ~HOLO"""
    Module19 template
    """
  end

  def action(:action_19a, _params, _component) do
    Module18.my_fun()
  end
end
