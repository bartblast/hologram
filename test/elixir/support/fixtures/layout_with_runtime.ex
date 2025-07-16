defmodule Hologram.Test.Fixtures.LayoutWithRuntime do
  use Hologram.Component
  alias Hologram.UI.Runtime

  @impl Component
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <Runtime />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
