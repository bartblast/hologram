defmodule Hologram.Test.Fixtures.Template.BindingsAggregator.Module1 do
  use Hologram.Component

  def init do
    %{
      c: 333,
      e: 444,
      f: 555
    }
  end

  def template do
    ~H"""
    """
  end
end
