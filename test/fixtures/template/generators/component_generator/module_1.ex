defmodule Hologram.Test.Fixtures.Template.ComponentGenerator.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    <div>test</div>
    """
  end
end
