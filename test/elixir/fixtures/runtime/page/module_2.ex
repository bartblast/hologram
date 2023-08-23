# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Page.Module2 do
  use Hologram.Page

  route "/module_2"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4

  def init(_params, client, server) do
    {put_state(client, :overriden, true), server}
  end

  def template do
    ~H"""
    Module2 template
    """
  end
end
