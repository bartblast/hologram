# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module2

  route "/hologram-test-fixtures-mix-tasks-holo-compiler-pagetomfapaths-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    Module1 template
    {fun_1a()}, {fun_1b()}
    """
  end

  def fun_1a, do: Module2.fun_2b()

  def fun_1b, do: :b
end
