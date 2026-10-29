defmodule Hologram.Test.Fixtures.Controller.Module45 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module45/:text"

  param :text, :string

  layout Hologram.Test.Fixtures.LayoutWithRuntime

  @impl Page
  def template do
    ~HOLO"""
    <input value={@text} /><p>{@text}</p>
    """
  end
end
