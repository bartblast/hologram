# A type of the app's own whose stored value loads as a struct, so a record's field of this type
# holds the struct.
defmodule HologramEcosystemTests.Ecto.Types.Stamp do
  use Ecto.Type

  @impl Ecto.Type
  def cast(%Date{} = value), do: {:ok, value}

  def cast(_value), do: :error

  @impl Ecto.Type
  def dump(%Date{} = value), do: {:ok, Date.to_iso8601(value)}

  def dump(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_binary(value), do: Date.from_iso8601(value)

  def load(_value), do: :error

  @impl Ecto.Type
  def type, do: :string
end
