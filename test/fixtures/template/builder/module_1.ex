defmodule Hologram.Test.Fixtures.Template.Builder.Module1 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Builder.Module2

  def template do
    ~H"""
    <div>test template</div>
    <Module2></Module2>
    """
  end

  # prevent unused alias compiler warning
  Module2
end
