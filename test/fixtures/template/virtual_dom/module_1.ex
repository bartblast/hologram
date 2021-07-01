defmodule Hologram.Test.Fixtures.Template.VirtualDOM.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    <div>test template</div>
    """
  end
end
