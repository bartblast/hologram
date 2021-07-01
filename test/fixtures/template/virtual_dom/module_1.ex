defmodule Hologram.Test.Fixtures.Template.VirtualDOM.Module1 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.VirtualDOM.Module2

  def template do
    ~H"""
    <div>test template</div>
    <Module2></Module2>
    """
  end
end
