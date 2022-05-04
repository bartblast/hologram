defmodule Hologram.Test.Fixtures.App.DefaultLayout do
  use Hologram.Layout

  def init(_conn) do
    %{}
  end

  def template do
    ~H"""
    """
  end
end
