# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Page.Module2 do
  use Hologram.Page

  route "/module_2"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4

  def init(_params, _conn), do: %{overridden: true}

  def template do
    ~H"""
    Module2 template
    """
  end
end
