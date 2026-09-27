# A module the app defines in Ash's namespace, for the test that the data flow rules still follow it:
# only Ash's and its extensions' own modules are opaque.
defmodule Ash.EcosystemProbe do
  def value, do: :probe
end
