# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageMfaCascades.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-page-mfa-cascades-module1"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    Module1 template
    """
  end

  def action(:test, _params, component) do
    module = Map
    module.get(%{a: 1}, :a)

    put_state(component, :result, nil)
  end
end
