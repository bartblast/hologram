# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.DefaultLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~H"""
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
