# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.DefaultLayout do
  @moduledoc false

  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~HOLO"""
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
