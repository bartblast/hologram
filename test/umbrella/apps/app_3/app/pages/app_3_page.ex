defmodule App3.Page do
  use Hologram.Page

  route "/app-3"

  layout App3.DefaultLayout

  def template do
    ~HOLO"""
    <h1>App 3 page</h1>
    <p id="message">Hello from app_3!</p>
    """
  end
end
