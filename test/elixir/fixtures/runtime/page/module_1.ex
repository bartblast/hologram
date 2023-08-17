defmodule Hologram.Test.Fixtures.Runtime.Page.Module1 do
  use Hologram.Page

  route "/module_1"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4

  @impl Page
  def template do
    ~H"""
    Module1 template
    """
  end
end
