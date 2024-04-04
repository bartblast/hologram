defmodule HologramFeatureTestsWeb.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature
    end
  end
end
