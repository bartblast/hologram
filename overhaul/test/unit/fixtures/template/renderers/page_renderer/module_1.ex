defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module1 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.PageRenderer.Module2
  alias Hologram.Test.Fixtures.Template.PageRenderer.Module3, warn: false

  layout Module2

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
    <Module3 id="component_3_id" />
    """
  end
end
