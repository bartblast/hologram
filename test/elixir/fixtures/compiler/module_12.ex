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

  def action(:action_12a, params, component) do
    Module7.my_fun_7a(params, component)
  end

  def action(:action_12b, params, component) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(ModuleWithoutBEAMFile, :my_fun, [params, component])
  end
end
