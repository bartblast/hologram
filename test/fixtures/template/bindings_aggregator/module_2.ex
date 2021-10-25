defmodule Hologram.Test.Fixtures.Template.BindingsAggregator.Module2 do
  use Hologram.Layout

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
