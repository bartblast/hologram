# A type of the app's own whose stored value is cast to a struct: the rules follow its cast, so a
# record's field of this type holds the struct.
defmodule HologramEcosystemTests.Ash.Types.Stamp do
  use Ash.Type

  @impl Ash.Type
  def cast_input(%Date{} = value, _constraints), do: {:ok, value}

  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(_value, _constraints), do: :error

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) when is_binary(value), do: Date.from_iso8601(value)

  def cast_stored(_value, _constraints), do: :error

  @impl Ash.Type
  def dump_to_native(%Date{} = value, _constraints), do: {:ok, Date.to_iso8601(value)}

  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(_value, _constraints), do: :error

  @impl Ash.Type
  def storage_type(_constraints), do: :string
end
