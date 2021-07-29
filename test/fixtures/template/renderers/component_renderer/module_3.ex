defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module3 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module1

  def template do
    ~H"""
    <div><Module1 /></div>
    """
  end
end
