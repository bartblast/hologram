defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module1 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Template.PageRenderer.Module2

  route "/test-route-1"

  def init(params, conn) do
    %{
      a: 123,
      c: params.c,
      d: conn.session.d
    }
  end

  def template do
    ~H"""
    page template assign {@a}, page template param {@c}, page template conn session {@d}
    """
  end
end
