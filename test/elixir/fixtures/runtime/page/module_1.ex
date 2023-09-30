defmodule Hologram.Test.Fixtures.Runtime.Page.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-page-module1"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4

  @impl Page
  def template do
    ~H"""
    Module1 template
    """
  end
end
