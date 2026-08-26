defmodule Hologram.DB.Codec do
  @moduledoc false

  @doc """
  Translates a value received from the Postgres driver into the Elixir term held by entity structs, per attribute type.
  nil stays nil, :enum text becomes an existing atom, :uuid 16-byte binaries become canonical lowercase uuid strings - values of the other admitted types pass through unchanged.
  An :enum label beginning with an uppercase letter names a module, and decodes to the module itself - modules are stored without their "Elixir." prefix.
  A :map value is a jsonb column's contents as the driver hands them back, keyed by strings - what those keys name is the caller's to know.
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

  def decode(value, :map), do: value

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
  Translates a value from its JSON form into the Elixir term held by entity structs, per attribute type - the inverse of encode_json/2, and the way a value written elsewhere is read back.
  Returns {:ok, value}, or :error for a value that is not the given type's JSON form.
  nil reads back as nil for every type, an ISO 8601 string becomes a :date or a :datetime, an :enum label becomes the atom or module it names - booleans, maps, numbers and strings are read as they are spelled, and a :uuid stays the string it is, its form being the model's to judge.
  A whole number reads back as a :float value, because a JSON writer spells 1.0 as 1 and the two are one number to it.
  Which type a JSON value carries is not recoverable from the value itself, since a :date, an :enum and a :uuid all arrive as strings - reading one back means knowing the attribute it belongs to, whose type the model states.
  """
  @spec decode_json(any, atom) :: {:ok, any} | :error
  def decode_json(value, type)

  def decode_json(nil, _type), do: {:ok, nil}

  def decode_json(value, :boolean) when is_boolean(value), do: {:ok, value}

  def decode_json(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  def decode_json(value, :datetime) when is_binary(value) do
    # from_iso8601/1 answers the UTC representation of whatever offset it was given, which is
    # the form encode/2 stores and the only one an entity struct holds.
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  def decode_json(value, :enum) when is_binary(value) do
    {:ok, decode_enum_label(value)}
  rescue
    ArgumentError -> :error
  end

  def decode_json(value, :float) when is_float(value), do: {:ok, value}

  def decode_json(value, :float) when is_integer(value) do
    {:ok, value * 1.0}
  rescue
    # An Elixir integer has arbitrary precision and a float is 64 bits, so promoting one past the
    # float range RAISES rather than saturating. Answered as a value this type cannot hold, which
    # is what it is - the alternative is the exception escaping a caller that handles only :error.
    ArithmeticError -> :error
  end

  def decode_json(value, :integer) when is_integer(value), do: {:ok, value}

  def decode_json(value, :map) when is_map(value), do: {:ok, value}

  def decode_json(value, :string) when is_binary(value), do: {:ok, value}

  def decode_json(value, :uuid) when is_binary(value), do: {:ok, value}

  def decode_json(_value, _type), do: :error

  @doc """
  Translates an Elixir term held by entity structs into the value the Postgres driver exchanges, per attribute type.
  nil stays nil, :datetime values are normalized to their UTC representation, :enum atoms become strings, :uuid strings become 16-byte binaries - values of the other admitted types pass through unchanged.
  An :enum value that is a module is stored under its name without the "Elixir." prefix, which is the spelling the model declares it with.
  A :map value is handed to the driver as it is spelled, and the jsonb column it is bound to holds it.
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

  def encode(value, :map), do: value

  def encode(value, :string), do: value

  def encode(value, :uuid) do
    value
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
  end

  @doc """
  Translates an Elixir term held by entity structs into its JSON form, per attribute type.
  nil stays nil, :date and :datetime values become ISO 8601 strings, :enum atoms become their labels - booleans, maps, numbers, strings and uuids pass through as they are spelled.
  This is how a value is stored in a jsonb column, where being queryable and legible is the point - it is not how a value is sent to a client, which the client-bound term encoder does.
  Which type a JSON value carries is not recoverable from the value itself, since a :date, an :enum and a :uuid all arrive as strings - reading one back means knowing the attribute it belongs to, whose type the model states.
  """
  @spec encode_json(any, atom) :: boolean | map | number | String.t() | nil
  def encode_json(value, type)

  def encode_json(nil, _type), do: nil

  def encode_json(value, :boolean), do: value

  def encode_json(value, :date), do: Date.to_iso8601(value)

  def encode_json(value, :datetime) do
    value
    |> encode(:datetime)
    |> DateTime.to_iso8601()
  end

  def encode_json(value, :enum), do: encode_enum_value(value)

  def encode_json(value, :float), do: value

  def encode_json(value, :integer), do: value

  def encode_json(value, :map), do: value

  def encode_json(value, :string), do: value

  def encode_json(value, :uuid), do: value

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
