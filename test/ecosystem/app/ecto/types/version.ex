# A parameterized type of the app's own whose stored value loads as a struct: the rules follow its
# load, so a record's field of this type holds the struct.
defmodule HologramEcosystemTests.Ecto.Types.Version do
  use Ecto.ParameterizedType

  @impl Ecto.ParameterizedType
  def cast(%Version{} = value, _params), do: {:ok, value}

  def cast(nil, _params), do: {:ok, nil}

  def cast(_value, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(%Version{} = value, _dumper, _params), do: {:ok, to_string(value)}

  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(_value, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  def init(opts), do: Map.new(opts)

  @impl Ecto.ParameterizedType
  def load(value, _loader, _params) when is_binary(value), do: Version.parse(value)

  def load(nil, _loader, _params), do: {:ok, nil}

  def load(_value, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def type(_params), do: :string
end
