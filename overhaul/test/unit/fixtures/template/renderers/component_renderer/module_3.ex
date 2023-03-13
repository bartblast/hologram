defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module3 do
  use Hologram.Component

  def init(props) do
    %{
      test_state: props.test_prop
    }
  end

  def template do
    ~H"""
    abc.{@test_state}.xyz
    """
  end
end
