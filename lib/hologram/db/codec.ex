defmodule Hologram.DB.Codec do
  @moduledoc false

  # In ASCII order, so that ids of the same width sort the way their numbers do.
  @base62_digits "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # The base62 digits any 128-bit number fits in. An id is always written with all of them.
  @id_width 22

  @doc """
  Translates a value received from the Postgres driver into the Elixir term held by entity structs, per attribute type.
  nil stays nil, :enum text becomes an existing atom, :id 16-byte binaries become their 22-character base62 form, :uuid 16-byte binaries become canonical lowercase uuid strings - values of the other admitted types pass through unchanged.
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

  def decode(<<number::128>>, :id), do: base62(number, @id_width, [])

  def decode(value, :integer), do: value

  def decode(value, :map), do: value

  def decode(value, :string), do: value

  def decode(value, :time), do: value

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

  # The first and last day a Postgres date column holds, as {year, month, day}.
  @first_column_day {-4713, 11, 24}
  @last_column_day {5_874_897, 12, 31}

  # The first and last instant a datetime can be stored at, in Unix microseconds. A timestamptz
  # column starts on the date column's first day. It ends far past 9999, but encode/2 goes through
  # DateTime.from_unix!/2, which stops there.
  @first_storable_datetime DateTime.to_unix(~U[-4713-11-24 00:00:00.000000Z], :microsecond)
  @last_storable_datetime DateTime.to_unix(~U[9999-12-31 23:59:59.999999Z], :microsecond)

  # The largest integer a JavaScript number holds exactly.
  @max_safe_integer 9_007_199_254_740_991

  @doc """
  Translates a value from its JSON form into the Elixir term held by entity structs, per attribute type - the inverse of encode_json/2, and the way a value written elsewhere is read back.
  Returns {:ok, value}, or :error for a value that is not the given type's JSON form.
  nil reads back as nil for every type, an ISO 8601 string becomes a :date (of any year a date column holds, as encode_json/2 spells one), a :datetime or a :time, an :enum label becomes the atom or module it names - booleans, maps, numbers and strings are read as they are spelled, and an :id or a :uuid stays the string it is, its form being the model's to judge.
  A whole number reads back as a :float value, because a JSON writer spells 1.0 as 1 and the two are one number to it.
  Which type a JSON value carries is not recoverable from the value itself, since a :date, an :enum, an :id and a :uuid all arrive as strings - reading one back means knowing the attribute it belongs to, whose type the model states.
  """
  @spec decode_json(any, atom) :: {:ok, any} | :error
  def decode_json(value, type)

  def decode_json(nil, _type), do: {:ok, nil}

  def decode_json(value, :boolean) when is_boolean(value), do: {:ok, value}

  def decode_json(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, :invalid_format} -> decode_wide_year_date(value)
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

  def decode_json(value, :id) when is_binary(value), do: {:ok, value}

  def decode_json(value, :integer) when is_integer(value), do: {:ok, value}

  def decode_json(value, :map) when is_map(value), do: {:ok, value}

  def decode_json(value, :string) when is_binary(value), do: {:ok, value}

  def decode_json(value, :time) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, _reason} -> :error
    end
  end

  def decode_json(value, :uuid) when is_binary(value), do: {:ok, value}

  def decode_json(_value, _type), do: :error

  @doc """
  Translates a value a browser sent into the Elixir term held by entity structs, per attribute type.
  Returns {:ok, value}, or :error for a value that is not the given type's form on the wire.

  A JavaScript number holds an integer exactly only within 2^53 - 1 either way, so an :integer past that travels as its decimal text, in the one spelling Integer.to_string/1 writes. A JSON number past it is refused, since a browser can't have sent it exactly, and so is text spelling an integer a number would have carried. Every other value reads as decode_json/2 reads it.
  """
  @spec decode_wire(any, atom) :: {:ok, any} | :error
  def decode_wire(value, type)

  def decode_wire(value, :integer) when is_integer(value) do
    if abs(value) <= @max_safe_integer, do: {:ok, value}, else: :error
  end

  # No integer a column holds takes more bytes than this, so longer text isn't worth parsing.
  def decode_wire(value, :integer) when is_binary(value) and byte_size(value) <= 20 do
    case Integer.parse(value) do
      {integer, ""} when abs(integer) > @max_safe_integer ->
        if Integer.to_string(integer) == value, do: {:ok, integer}, else: :error

      _other ->
        :error
    end
  end

  def decode_wire(value, :integer) when is_binary(value), do: :error

  def decode_wire(value, type), do: decode_json(value, type)

  @doc """
  Translates an Elixir term held by entity structs into the value the Postgres driver exchanges, per attribute type.
  nil stays nil, :datetime values are normalized to their UTC representation, :time values to microsecond precision, :enum atoms become strings, :id and :uuid strings become 16-byte binaries - values of the other admitted types pass through unchanged.
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

  def encode(value, :id) do
    number =
      for <<char <- value>>, reduce: 0 do
        acc -> acc * 62 + base62_digit_value(char)
      end

    <<number::128>>
  end

  def encode(value, :integer), do: value

  def encode(value, :map), do: value

  def encode(value, :string), do: value

  # A time column is time(6), so a value read back from one always carries six fractional digits
  # while a value the application wrote carries whatever its literal spelled. Those are one time
  # and must be one wire spelling, the client comparing times of day as plain strings - so a
  # value goes out at full precision, exactly as a :datetime does. Only the digits it is spelled
  # with change, never the amount.
  def encode(%Time{microsecond: {microsecond, _precision}} = value, :time) do
    %{value | microsecond: {microsecond, 6}}
  end

  def encode(value, :uuid) do
    value
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
  end

  @doc """
  Translates an Elixir term held by entity structs into its JSON form, per attribute type.
  nil stays nil, :date and :datetime values become ISO 8601 strings, a :time value becomes one at full microsecond precision whatever it was written at, :enum atoms become their labels - booleans, maps, numbers, strings, ids and uuids pass through as they are spelled.
  This is how a value is stored in a jsonb column, where being queryable and legible is the point - it is not how a value is sent to a client, which the client-bound term encoder does.
  Which type a JSON value carries is not recoverable from the value itself, since a :date, an :enum, an :id and a :uuid all arrive as strings - reading one back means knowing the attribute it belongs to, whose type the model states.
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

  def encode_json(value, :id), do: value

  def encode_json(value, :integer), do: value

  def encode_json(value, :map), do: value

  def encode_json(value, :string), do: value

  def encode_json(value, :time) do
    value
    |> encode(:time)
    |> Time.to_iso8601()
  end

  def encode_json(value, :uuid), do: value

  @doc """
  Translates an Elixir term held by entity structs into the JSON form a browser reads it from, per attribute type.

  A JavaScript number holds an integer exactly only within 2^53 - 1 either way, so an :integer past that travels as its decimal text. Every other value is spelled as encode_json/2 spells it. The oplog stays on encode_json/2, since it matches stored values as JSON numbers.
  """
  @spec encode_wire(any, atom) :: boolean | map | number | String.t() | nil
  def encode_wire(value, type)

  def encode_wire(value, :integer) when is_integer(value) and abs(value) > @max_safe_integer do
    Integer.to_string(value)
  end

  def encode_wire(value, type), do: encode_json(value, type)

  @doc """
  Translates an atom into its Postgres enum label - a module without its "Elixir." prefix, a plain atom as it is spelled.
  """
  @spec encode_enum_value(atom) :: String.t()
  def encode_enum_value(value) do
    value
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  @doc """
  Returns true if a date column can hold the given date, which runs from -4713-11-24 to 5874897-12-31.
  A date in another calendar is never storable, since the driver encodes only Calendar.ISO.
  """
  @spec storable_date?(Date.t()) :: boolean
  def storable_date?(%Date{calendar: Calendar.ISO, year: year, month: month, day: day}) do
    {year, month, day} >= @first_column_day and {year, month, day} <= @last_column_day
  end

  def storable_date?(%Date{}), do: false

  @doc """
  Returns true if the given datetime can be stored, which takes an instant from -4713-11-24T00:00:00Z to 9999-12-31T23:59:59.999999Z.
  The instant is what's judged, so the offsets a datetime carries can move it across either end. A struct literal can hold anything in them, and one that isn't an integer names no instant.
  """
  @spec storable_datetime?(DateTime.t()) :: boolean
  def storable_datetime?(%DateTime{std_offset: std_offset, utc_offset: utc_offset} = value)
      when is_integer(std_offset) and is_integer(utc_offset) do
    microseconds = DateTime.to_unix(value, :microsecond)

    microseconds >= @first_storable_datetime and microseconds <= @last_storable_datetime
  end

  def storable_datetime?(%DateTime{}), do: false

  # Date.to_iso8601/1 spells a year past 9999 with all its digits, and Date.from_iso8601/1 reads no
  # more than four - so encode_json/2 writes dates its own inverse can't read, and a browser writing
  # one would have it refused. Read here only as far as a date column reaches, 5874897-12-31: the
  # driver writes a day count into 32 bits and drops what overflows, so a later day would be stored
  # as some other one, and none below year -9999 fits at all. A datetime needs no such reading:
  # DateTime.from_unix!/2, which every datetime is stored through, stops at 9999.
  defp decode_wide_year_date(value) do
    with [_value | fields] <- Regex.run(~r/\A([1-9]\d{4,6})-(\d{2})-(\d{2})\z/, value),
         [year, month, day] = Enum.map(fields, &String.to_integer/1),
         {:ok, date} <- Date.new(year, month, day),
         true <- storable_date?(date) do
      {:ok, date}
    else
      _no_date -> :error
    end
  end

  defp base62(_number, 0, digits), do: List.to_string(digits)

  defp base62(number, width, digits) do
    digit = :binary.at(@base62_digits, rem(number, 62))
    base62(div(number, 62), width - 1, [digit | digits])
  end

  defp base62_digit_value(char) when char in ?0..?9, do: char - ?0
  defp base62_digit_value(char) when char in ?A..?Z, do: char - ?A + 10
  defp base62_digit_value(char) when char in ?a..?z, do: char - ?a + 36
end
