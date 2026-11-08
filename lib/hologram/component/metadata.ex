defmodule Hologram.Component.Metadata do
  @moduledoc false

  # secret_keys names the component's secret state entries. State and props share one set of names,
  # the one the template reads, so a name alone says which value it is.
  defstruct secret_keys: []

  @type t :: %__MODULE__{secret_keys: [atom]}
end
