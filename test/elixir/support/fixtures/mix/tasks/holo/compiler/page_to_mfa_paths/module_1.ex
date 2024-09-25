# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-mix-tasks-holo-compiler-pagetomfapaths-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H"""
    Module1 template
    {fun_1()}, {fun_2()}
    """
  end

  def fun_2, do: :b

  def fun_1, do: DateTime.utc_now()
end
