# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-mix-tasks-holo-compiler-pageexfilesizes-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    Module1 template
    {fun_1()}, {fun_2()}
    """
  end

  def fun_2, do: :b

  def fun_1, do: :a
end
