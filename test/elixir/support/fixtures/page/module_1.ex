defmodule Hologram.Test.Fixtures.Page.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-page-module1"

  layout Hologram.Test.Fixtures.Page.Module4

  @impl Page
  def template do
    ~HOLO"""
    Module1 template
    """
  end
end
