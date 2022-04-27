defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    abc.{@test_prop}.xyz
    """
  end
end
