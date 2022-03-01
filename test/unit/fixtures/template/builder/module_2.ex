defmodule Hologram.Test.Fixtures.Template.Builder.Module2 do
  use Hologram.Component

  def template do
    ~H"""
    <div>test template</div>
    """
  end
end
