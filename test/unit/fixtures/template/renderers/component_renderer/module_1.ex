defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module1 do
  use Hologram.Component

  def init(_props) do
    %{}
  end

  def template do
    ~H"""
    abc.{@test_prop}.xyz
    """
  end
end
