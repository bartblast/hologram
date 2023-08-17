defmodule Hologram.Test.Fixtures.Runtime.Component.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    Module1 template
    """
  end
end
