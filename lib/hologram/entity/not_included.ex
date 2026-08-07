defmodule Hologram.Entity.NotIncluded do
  @moduledoc false

  # The default value of an entity struct's relationship embed and to-many fields -
  # it marks a relationship the producing query did not include. Included
  # relationships hold nil (to-one, reference absent), an entity struct (to-one,
  # reference present), or a list of entity structs (to-many).

  @enforce_keys [:relationship]

  defstruct [:relationship]

  @type t :: %__MODULE__{relationship: atom}
end
