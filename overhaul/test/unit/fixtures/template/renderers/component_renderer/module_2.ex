defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module2 do
  use Hologram.Component

  def init(_props) do
    %{
      test_state: 1
    }
  end

  def template do
    ~H"""
    {@test_state}.{@test_prop}
    """
  end
end
