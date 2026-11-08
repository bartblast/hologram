defmodule Hologram.Component.Redacted do
  @moduledoc false

  # Stands in for a secret value while a component struct is inspected (see the Inspect
  # implementation for Hologram.Component), so the value prints as **redacted**.
  defstruct []

  @type t :: %__MODULE__{}
end

defimpl Inspect, for: Hologram.Component.Redacted do
  alias Hologram.Component.Redacted

  @spec inspect(Redacted.t(), Inspect.Opts.t()) :: String.t()
  def inspect(_redacted, _opts), do: "**redacted**"
end
