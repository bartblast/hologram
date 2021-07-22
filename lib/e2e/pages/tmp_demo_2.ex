defmodule Demo.TmpDemo2 do
  use Hologram.Page

  route "/demo/page2"

  def state do
    %{}
  end

  def render do
    ~H"""
    Page2
    """
  end
end
