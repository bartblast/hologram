# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module12 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Module7

  route "/hologram-test-fixtures-compiler-module12"

  layout Hologram.Test.Fixtures.Compiler.Module6

  def template do
    ~H"""
    Module12 template
    """
  end

  def action(:action_12a, params, client) do
    Module7.my_fun_7a(params, client)
  end

  def action(:action_12b, params, client) do
    apply(ModuleWithoutBEAMFile, :my_fun, [params, client])
  end
end
