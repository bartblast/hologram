defmodule Hologram.Test.Fixtures.Template.ComponentEncoder.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    <div>test</div>
    """
  end
end
