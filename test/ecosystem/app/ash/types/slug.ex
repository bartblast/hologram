# A type of the app's own, not built on an Ash type: the rules follow its cast.
defmodule HologramEcosystemTests.Ash.Types.Slug do
  use Ash.Type

  @impl Ash.Type
  def cast_input(value, _constraints) when is_binary(value), do: {:ok, String.downcase(value)}

  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(_value, _constraints), do: :error

  @impl Ash.Type
  def cast_stored(value, _constraints) when is_binary(value) or is_nil(value), do: {:ok, value}

  def cast_stored(_value, _constraints), do: :error

  @impl Ash.Type
  def dump_to_native(value, _constraints) when is_binary(value) or is_nil(value), do: {:ok, value}

  def dump_to_native(_value, _constraints), do: :error

  @impl Ash.Type
  def storage_type(_constraints), do: :string
end
