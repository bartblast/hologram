defmodule HologramE2E.Page6 do
  use Hologram.Page

  route "/e2e/page-6"

  def init do
    %{}
  end

  def template do
    ~H"""
    <h1>Page 6</h1>
    <Link to={HologramE2E.Page7} class="test-class" id="test-id">
      Anchor text
    </Link>
    """
  end
end
