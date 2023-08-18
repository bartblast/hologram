defmodule Hologram.Test.Fixtures.Runtime.Templatable.Module1 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Runtime.Templatable.Module2

  @impl Component
  def template do
    ~H"""
    Remote function call result = {Module2.fun_a()}
    """
  end
end
