defmodule Hologram.Test.Fixtures.Runtime.Module5 do
  use Hologram.Page

  def state do
    %{}
  end

  def template do
    ~H"""
      test_template
    """
  end
end
