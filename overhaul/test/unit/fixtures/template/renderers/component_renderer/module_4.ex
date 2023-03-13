defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module4 do
  use Hologram.Component

  def init(props, conn) do
    %{
      test_state_1: props.test_prop,
      test_state_2: conn.session.test_session_key
    }
  end

  def template do
    ~H"""
    {@test_state_1}.{@test_state_2}
    """
  end
end
