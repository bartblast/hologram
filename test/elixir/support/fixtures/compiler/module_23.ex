# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module23 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Module18
  alias Hologram.Test.Fixtures.Compiler.Module22

  route "/hologram-test-fixtures-compiler-module23"

  layout Hologram.Test.Fixtures.Compiler.Module6

  def template do
    ~HOLO"""
    Module23 template
    """
  end

  def action(:action_23a, _params, _component) do
    {Module18.my_fun(), Module22.my_fun()}
  end
end
