defmodule Hologram.Sync.PackedIds do
  @moduledoc false

  # Ids packed into one binary: each id's 16 bytes, sorted, each id once, and a pair of ids as 32.
  # What sync keeps of rows in bulk - the ids a batch touched, handed to every session on a node,
  # and the ids a session's client holds - is kept this way rather than as sets of strings.
  #
  # Two reasons, both about size. A packed id takes 16 bytes where a string in a set takes several
  # times that. And a binary over 64 bytes lives outside the process heap and is passed by
  # reference, so one handed to thousands of sessions exists once, where a set of strings would be
  # copied into each of them.
  #
  # Being sorted is what makes a lookup a search. Nothing here checks it - that would read every
  # id - so a binary is only ever made by this module, or by the statement `pairs_sql/2` gives.

  alias Hologram.DB.Codec

  defguardp ids?(packed) when is_binary(packed) and rem(byte_size(packed), 16) == 0

  defguardp pairs?(packed) when is_binary(packed) and rem(byte_size(packed), 32) == 0

  @doc """
  Returns the given packed ids with the given ids taken out, an id not there passed over.

  Copies the packed ids once, whatever the number of ids taken out.
  """
  @spec delete(binary, Enumerable.t()) :: binary
  def delete(packed, ids) when ids?(packed) do
    count = div(byte_size(packed), 16)

    {slices, from} =
      ids
      |> sorted_encoded()
      |> Enum.reduce({[], 0}, fn id, {slices, from} ->
        index = lower_bound(packed, id, 16, 16, from, count)

        if index < count and binary_part(packed, index * 16, 16) == id do
          {[slice(packed, from, index) | slices], index + 1}
        else
          {slices, from}
        end
      end)

    finish(packed, slices, from, count)
  end

  @doc """
  Returns the given packed ids with the given ids added, still in order, an id already there kept
  once.

  Copies the packed ids once, whatever the number of ids added.
  """
  @spec insert(binary, Enumerable.t()) :: binary
  def insert(packed, ids) when ids?(packed) do
    count = div(byte_size(packed), 16)

    {slices, from} =
      ids
      |> sorted_encoded()
      |> Enum.reduce({[], 0}, fn id, {slices, from} ->
        index = lower_bound(packed, id, 16, 16, from, count)

        if index < count and binary_part(packed, index * 16, 16) == id do
          {slices, from}
        else
          {[id, slice(packed, from, index) | slices], index}
        end
      end)

    finish(packed, slices, from, count)
  end

  @doc """
  Returns the left ids of the given pairs whose right id is the given one, in order. The pairs are
  ordered by their left id, so finding these reads every pair.
  """
  @spec lefts_of(binary, String.t()) :: list(String.t())
  def lefts_of(packed_pairs, right_id) when pairs?(packed_pairs) do
    right = encode(right_id)

    for <<left::binary-size(16), ^right::binary-size(16) <- packed_pairs>>,
      do: Codec.decode(left, :uuid)
  end

  @doc """
  Returns whether the given id is among the given packed ids - found by a search, in a number of
  steps that grows with the log of their count.
  """
  @spec member?(binary, String.t()) :: boolean
  def member?(packed, id) when ids?(packed) do
    encoded = encode(id)
    count = div(byte_size(packed), 16)
    index = lower_bound(packed, encoded, 16, 16, 0, count)

    index < count and binary_part(packed, index * 16, 16) == encoded
  end

  @doc """
  Returns the given ids packed: each id's 16 bytes, in order, an id given twice packed once. An id
  that doesn't encode to 16 bytes raises.
  """
  @spec pack(Enumerable.t()) :: binary
  def pack(ids) do
    ids
    |> sorted_encoded()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns the given pairs of ids packed: each pair's two ids, 32 bytes, in order, a pair given twice
  packed once.
  """
  @spec pack_pairs(Enumerable.t()) :: binary
  def pack_pairs(pairs) do
    pairs
    |> Enum.map(fn {left, right} -> encode(left) <> encode(right) end)
    |> Enum.sort()
    |> Enum.dedup()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns whether the given pair is among the given packed pairs.
  """
  @spec pair_member?(binary, String.t(), String.t()) :: boolean
  def pair_member?(packed_pairs, left_id, right_id) when pairs?(packed_pairs) do
    pair = encode(left_id) <> encode(right_id)
    count = div(byte_size(packed_pairs), 32)
    index = lower_bound(packed_pairs, pair, 32, 32, 0, count)

    index < count and binary_part(packed_pairs, index * 32, 32) == pair
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
  Returns the right ids of the given pairs whose left id is the given one, in order - found by a
  search, since the pairs are ordered by their left id.
  """
  @spec rights_of(binary, String.t()) :: list(String.t())
  def rights_of(packed_pairs, left_id) when pairs?(packed_pairs) do
    left = encode(left_id)
    count = div(byte_size(packed_pairs), 32)
    index = lower_bound(packed_pairs, left, 16, 32, 0, count)

    take_rights(packed_pairs, left, index, count, [])
  end

  @doc """
  Splits the given packed ids into those among the given packed set and those not, both packed -
  each looked up by a search, so the cost follows the ids split rather than the size of the set.
  """
  @spec split(binary, binary) :: {binary, binary}
  def split(packed_set, packed_ids) when ids?(packed_set) and ids?(packed_ids) do
    count = div(byte_size(packed_set), 16)

    {inside, outside} =
      for <<id::binary-size(16) <- packed_ids>>, reduce: {[], []} do
        {inside, outside} ->
          index = lower_bound(packed_set, id, 16, 16, 0, count)

          if index < count and binary_part(packed_set, index * 16, 16) == id do
            {[id | inside], outside}
          else
            {inside, [id | outside]}
          end
      end

    {pack_reversed(inside), pack_reversed(outside)}
  end

  @doc """
  Returns the ids packed in the given binary (see `pack/1`), in order, each in the spelling
  Hologram generates.
  """
  @spec unpack(binary) :: list(String.t())
  def unpack(packed) when ids?(packed) do
    for <<id::binary-size(16) <- packed>>, do: Codec.decode(id, :uuid)
  end

  @doc """
  Returns the pairs of ids packed in the given binary (see `pack_pairs/1`), in order.
  """
  @spec unpack_pairs(binary) :: list({String.t(), String.t()})
  def unpack_pairs(packed) when pairs?(packed) do
    for <<left::binary-size(16), right::binary-size(16) <- packed>> do
      {Codec.decode(left, :uuid), Codec.decode(right, :uuid)}
    end
  end

  # Something that isn't a uuid would pack to more or fewer bytes and shift every id after it.
  defp encode(id) do
    <<_bytes::binary-size(16)>> = Codec.encode(id, :uuid)
  end

  defp finish(packed, slices, from, count) do
    [slice(packed, from, count) | slices]
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  # The index of the first entry at or past the given key among the entries from `low` up to
  # `high`, each entry `size` bytes and compared by its first `key_size`.
  defp lower_bound(_packed, _key, _key_size, _size, low, high) when low >= high, do: low

  defp lower_bound(packed, key, key_size, size, low, high) do
    middle = div(low + high, 2)

    if binary_part(packed, middle * size, key_size) < key do
      lower_bound(packed, key, key_size, size, middle + 1, high)
    else
      lower_bound(packed, key, key_size, size, low, middle)
    end
  end

  # One id is handed back as the very binary it was matched from - a part of the binary it was
  # split from, which, held onto, would keep that whole binary alive - so it is copied.
  defp pack_reversed([single]), do: :binary.copy(single)

  defp pack_reversed(encoded_ids) do
    encoded_ids
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp slice(packed, from, to), do: binary_part(packed, from * 16, (to - from) * 16)

  defp sorted_encoded(ids) do
    ids
    |> Enum.map(&encode/1)
    |> Enum.sort()
    |> Enum.dedup()
  end

  defp take_rights(packed_pairs, left, index, count, rights) when index < count do
    case binary_part(packed_pairs, index * 32, 32) do
      <<^left::binary-size(16), right::binary-size(16)>> ->
        take_rights(packed_pairs, left, index + 1, count, [Codec.decode(right, :uuid) | rights])

      _other_left ->
        Enum.reverse(rights)
    end
  end

  defp take_rights(_packed_pairs, _left, _index, _count, rights), do: Enum.reverse(rights)
end
