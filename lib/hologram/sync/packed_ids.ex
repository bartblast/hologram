defmodule Hologram.Sync.PackedIds do
  @moduledoc false

  # Ids packed into one binary: each id's 16 bytes, sorted, and a pair of ids as 32. What sync
  # keeps of rows in bulk - the ids a batch touched, handed to every session on a node, and the ids
  # a session's client holds - is kept this way rather than as sets of strings.
  #
  # Two reasons, both about size. A packed id takes 16 bytes where a string in a set takes several
  # times that. And a binary over 64 bytes lives outside the process heap and is passed by
  # reference, so one handed to thousands of sessions exists once, where a set of strings would be
  # copied into each of them.

  alias Hologram.DB.Codec

  @doc """
  Returns the given ids packed: each id's 16 bytes, in order. An id that doesn't encode to 16 bytes
  raises.
  """
  @spec pack(Enumerable.t()) :: binary
  def pack(ids) do
    ids
    |> Enum.map(&encode/1)
    |> Enum.sort()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns the given pairs of ids packed: each pair's two ids, 32 bytes, in order.
  """
  @spec pack_pairs(Enumerable.t()) :: binary
  def pack_pairs(pairs) do
    pairs
    |> Enum.map(fn {left, right} -> encode(left) <> encode(right) end)
    |> Enum.sort()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns the SQL expression packing the rows a statement selects, as pairs of the given uuid
  columns, the way `pack_pairs/1` packs them - one value, empty when no row is selected. Postgres
  orders uuids by their bytes, so its order is the order `pack_pairs/1` sorts into.

  Packed where the rows are rather than after: a big set comes back as one value, where decoding
  it row by row and packing it here costs several times as long as reading it.
  """
  @spec pairs_sql(String.t(), String.t()) :: String.t()
  def pairs_sql(left_column, right_column) do
    ~s|COALESCE(string_agg(uuid_send(#{left_column}) \|\| uuid_send(#{right_column}), ''::bytea | <>
      ~s|ORDER BY #{left_column}, #{right_column}), ''::bytea)|
  end

  @doc """
  Returns the ids packed in the given binary (see `pack/1`), in order, each in the spelling
  Hologram generates.
  """
  @spec unpack(binary) :: list(String.t())
  def unpack(packed) when is_binary(packed) and rem(byte_size(packed), 16) == 0 do
    for <<id::binary-size(16) <- packed>>, do: Codec.decode(id, :uuid)
  end

  @doc """
  Returns the pairs of ids packed in the given binary (see `pack_pairs/1`), in order.
  """
  @spec unpack_pairs(binary) :: list({String.t(), String.t()})
  def unpack_pairs(packed) when is_binary(packed) and rem(byte_size(packed), 32) == 0 do
    for <<left::binary-size(16), right::binary-size(16) <- packed>> do
      {Codec.decode(left, :uuid), Codec.decode(right, :uuid)}
    end
  end

  # Something that isn't a uuid would pack to more or fewer bytes and shift every id after it.
  defp encode(id) do
    <<_bytes::binary-size(16)>> = Codec.encode(id, :uuid)
  end
end
