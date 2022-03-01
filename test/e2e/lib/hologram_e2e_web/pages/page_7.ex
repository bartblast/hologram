defmodule HologramE2E.Page7 do
  use Hologram.Page

  route "/e2e/page-7"

  def init do
    %{}
  end

  def template do
    ~H"""
    <h1>Page 7</h1>
    page 7 template
    """
  end
end
