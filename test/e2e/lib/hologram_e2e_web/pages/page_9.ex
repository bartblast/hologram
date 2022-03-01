defmodule HologramE2E.Page9 do
  use Hologram.Page

  route "/e2e/page-9"

  def init do
    %{
      condition_1: 123,
      condition_2: nil
    }
  end

  def template do
    ~H"""
    <h1>Page 9</h1>
    <div id="div-1" if={@condition_1}>Element displayed</div>
    <div id="div-2" if={@condition_2}>Element not displayed</div>
    """
  end
end
