# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Page.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-page-module2"

  layout Hologram.Test.Fixtures.Page.Module4

  def init(_params, component, server) do
    {put_state(component, :overriden, true), server}
  end

  def template do
    ~HOLO"""
    Module2 template
    """
  end
end
