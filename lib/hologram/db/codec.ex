defmodule Hologram.DB.Codec do
  @moduledoc false

  @doc """
  Translates a value received from the Postgres driver into the Elixir term held by entity structs, per attribute type.
  nil stays nil, :enum text becomes an existing atom, :uuid 16-byte binaries become canonical lowercase uuid strings - values of the other admitted types pass through unchanged.
  An :enum label beginning with an uppercase letter names a module, and decodes to the module itself - modules are stored without their "Elixir." prefix.
  The inverse of encode/2 - the round-trip is the per-type contract.
  """
  @spec decode(any, atom) :: any
  def decode(value, type)

  def decode(nil, _type), do: nil

  def decode(value, :boolean), do: value

  def decode(value, :date), do: value

  def decode(value, :datetime), do: value

  def decode(value, :enum), do: decode_enum_label(value)

  def decode(value, :float), do: value

  def decode(value, :integer), do: value

  def decode(value, :string), do: value

  def decode(value, :uuid) do
    <<part_1::binary-size(8), part_2::binary-size(4), part_3::binary-size(4),
      part_4::binary-size(4), part_5::binary-size(12)>> = Base.encode16(value, case: :lower)

    "#{part_1}-#{part_2}-#{part_3}-#{part_4}-#{part_5}"
  end

  @doc """
  Translates a Postgres enum label into the atom it names - a module for a label beginning with an uppercase letter, a plain atom otherwise.
  """
  @spec decode_enum_label(String.t()) :: atom
  def decode_enum_label(<<first_byte, _rest::binary>> = label) when first_byte in ?A..?Z do
    String.to_existing_atom("Elixir." <> label)
  end

  def decode_enum_label(label), do: String.to_existing_atom(label)

  @doc """
  Translates an Elixir term held by entity structs into the value the Postgres driver exchanges, per attribute type.
  nil stays nil, :datetime values are normalized to their UTC representation, :enum atoms become strings, :uuid strings become 16-byte binaries - values of the other admitted types pass through unchanged.
  An :enum value that is a module is stored under its name without the "Elixir." prefix, which is the spelling the model declares it with.
  The inverse of decode/2 - the round-trip is the per-type contract.
  """
  @spec encode(any, atom) :: any
  def encode(value, type)

  def encode(nil, _type), do: nil

  def encode(value, :boolean), do: value

  def encode(value, :date), do: value

  def encode(value, :datetime) do
    # DateTime.shift_zone/2 fails for non-UTC sources under Elixir's default UTC-only
    # time zone database - the Unix round-trip normalizes any DateTime to its UTC
    # representation using the offsets embedded in the struct, with no tzdata dependency.
    value
    |> DateTime.to_unix(:microsecond)
    |> DateTime.from_unix!(:microsecond)
  end

  def encode(value, :enum), do: encode_enum_value(value)

  def encode(value, :float), do: value

  def encode(value, :integer), do: value

  def encode(value, :string), do: value

  def encode(value, :uuid) do
    value
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
  end

  @doc """
  Translates an atom into its Postgres enum label - a module without its "Elixir." prefix, a plain atom as it is spelled.
  """
  @spec encode_enum_value(atom) :: String.t()
  def encode_enum_value(value) do
    value
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end
end
