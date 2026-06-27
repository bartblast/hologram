defmodule HologramFeatureTests.Middleware.BasePage do
  defmacro __using__(_opts) do
    quote do
      use Hologram.Page

      layout HologramFeatureTests.Components.DefaultLayout

      middleware HologramFeatureTests.Middleware.Shared
    end
  end
end
