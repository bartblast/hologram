defmodule Counter do
  use Hologram.Component

  def template do
    ~H"""
    <div>Hello World {{ @counter }}</div>
    """
  end
end
