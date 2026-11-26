defmodule Hologram.Entity.NotIncluded do
  @moduledoc false

  # The default value of an entity struct's relationship embed and to-many fields, and of its
  # derived fields - it marks a field the producing query did not include. Included
  # relationships hold nil (to-one, reference absent), an entity struct (to-one, reference
  # present), or a list of entity structs (to-many). The internal __meta__ map names the field
  # the placeholder stands in for, as %{field: name}.

  defstruct __meta__: %{}

  @type t :: %__MODULE__{__meta__: map}
end
