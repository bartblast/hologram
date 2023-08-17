defmodule Hologram.Test.Fixtures.Runtime.Page.Module3 do
  use Hologram.Page

  route "/module_3"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4, a: 1, b: 2

  def template do
    ~H"""
    Module3 template
    """
  end
end
