defmodule Hologram.Test.Fixtures.Template.Module1 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Module2

  @impl Component
  def template do
    ~HOLO"""
    Remote function call result = {Module2.fun_a()}
    """
  end
end
