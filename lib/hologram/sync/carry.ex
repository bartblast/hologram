defmodule Hologram.Sync.Carry do
  @moduledoc false

  # What a page's own render resolved - its rows, and the counts nothing but a number came back
  # for - gathered as it renders and handed to the client with the page.
  #
  # What it buys: from the first client render, every derived field holding a query answers from
  # the client's own database rather than from a value the server passed down - no second
  # evaluation path, no swap when the stream finishes filling. The two executors agreeing is what
  # makes that first render match the HTML the server sent.
  #
  # Rows are spelled the way a frame spells them, so the client reads them through the same
  # ingest as everything else. What arrives this way is applied INSERT-ONLY there: what a page
  # carries can be older than what the client already holds - a page rendered at one moment can
  # land after the stream delivered a later change to the same row - and overwriting would put
  # back a value nothing would correct.
  #
  # Gathered in the process dictionary rather than threaded through the render: what a render
  # resolved is ambient to it, the way the acting user is, and the alternative is a new argument
  # on every render function. Both are request-scoped and neither outlives the response.

  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Query
  alias Hologram.Query.Window
  alias Hologram.Sync.Frame

  @key {__MODULE__, :entities}
  @count_types_key {__MODULE__, :count_types}
  @counts_key {__MODULE__, :counts}
  @grant_scopes_key {__MODULE__, :grant_scopes}

  # The largest integer a JavaScript Number holds exactly, Number.MAX_SAFE_INTEGER.
  @max_safe_integer 9_007_199_254_740_991

  @doc """
  Clears what a previous render gathered and returns :ok.

  A render ends by taking what it gathered, so this is what covers the render that does not end -
  one that raises leaves its rows behind, and the process serving the next request would hand
  them to a page they never belonged to.
  """
  @spec start() :: :ok
  def start do
    Process.delete(@key)
    Process.delete(@count_types_key)
    Process.delete(@counts_key)

    # Armed rather than cleared: a permission check outside a render finds no set here and
    # records nothing, which is what keeps the trusted paths (commands, mix tasks, IEx) free of
    # this entirely.
    Process.put(@grant_scopes_key, MapSet.new())

    :ok
  end

  @doc """
  Records the given count under the key naming the derived field that answered it.

  A counting query answers with a number and no rows, so nothing about it can be re-derived from
  the rows a page carries - the client is told the number itself, and holds it until its own database is
  complete enough to count.

  The key names the component, the derived field and the normalized query term it ran, spelled the
  way the client spells its own (see `spell_query/1`). The query holds every value it reads, so a
  changed value is a changed key, and the client never shows this number for a query the server
  didn't count. Two instances of one component running one query share a key, and the number.

  The entity types the count reads are recorded under the same key (see
  `Hologram.Query.Window.entity_types/1`), spelled as the client names a type: the client counts for
  itself once it holds every row of each of them it may see.
  """
  @spec collect_count(module, atom, Query.t(), integer) :: :ok
  def collect_count(module, name, term, count) do
    key = count_key(module, name, term)

    # The key spells the whole query, so a key already recorded reads the same types.
    count_types =
      @count_types_key
      |> Process.get(%{})
      |> Map.put_new_lazy(key, fn ->
        term
        |> Window.entity_types()
        |> Enum.map(&Codec.encode_enum_value/1)
      end)

    Process.put(@counts_key, Map.put(gathered_counts(), key, count))
    Process.put(@count_types_key, count_types)

    :ok
  end

  @doc """
  Records that a permission check asked the grant store about the given user and scope, and
  returns :ok. Recording only happens while a render is gathering - outside one this is a no-op,
  so the trusted paths that check permissions without rendering pay nothing.

  A check asks whether a grant EXISTS - it reads no rows, so there is nothing for the entity
  collector to gather. What is kept is the question, which is what the rows answering it are
  looked up by when the render ends.
  """
  @spec record_grant_scope(String.t() | nil, tuple | atom) :: :ok
  def record_grant_scope(user_id, scope) do
    case Process.get(@grant_scopes_key) do
      nil ->
        :ok

      scopes ->
        Process.put(@grant_scopes_key, MapSet.put(scopes, {user_id, scope}))

        :ok
    end
  end

  @doc """
  Records the entities the given query result holds - the rows themselves and everything they
  embed, however deep.

  A row reached more than once - in several places of one result, or by several results - is
  recorded once, carrying every relationship any of its copies included.

  A result that is a count rather than rows holds no entity and records nothing.
  """
  @spec collect(any) :: :ok
  def collect(result) do
    collected =
      result
      |> entities()
      |> Enum.reduce(gathered(), fn entity, acc ->
        Map.update(acc, key(entity), entity, &Entity.merge_copies(&1, entity))
      end)

    Process.put(@key, collected)

    :ok
  end

  @doc """
  Returns the rows gathered so far, grouped the way a frame groups them - by op, then by entity
  type - and clears what was gathered.

  Nothing gathered answers with an empty map rather than an empty put, since a page whose props
  read no rows has nothing to say rather than something empty to say. Each row carries the server's
  verdicts for the given user, the render's, as a frame's put does (see
  `Hologram.Sync.Frame.row_verdicts/2`).
  """
  @spec take(Hologram.Server.identity_id() | nil) :: %{
          optional(:put_entity) => %{String.t() => list(map)}
        }
  def take(actor_user_id) do
    entities = Map.values(gathered())

    Process.delete(@key)

    if entities == [] do
      %{}
    else
      %{put_entity: group(entities, actor_user_id)}
    end
  end

  @doc """
  Returns the entity types each count gathered so far reads, keyed as the counts are (see
  `collect_count/4`), and clears what was gathered.
  """
  @spec take_count_types() :: %{String.t() => [String.t()]}
  def take_count_types do
    count_types = Process.get(@count_types_key, %{})

    Process.delete(@count_types_key)

    count_types
  end

  @doc """
  Returns the counts gathered so far, keyed by derived field, and clears what was gathered.
  """
  @spec take_counts() :: %{String.t() => integer}
  def take_counts do
    counts = gathered_counts()

    Process.delete(@counts_key)

    counts
  end

  @doc """
  Returns the {user id, scope} pairs the render's permission checks asked about, and clears them.
  """
  @spec take_grant_scopes() :: MapSet.t({String.t() | nil, tuple | atom})
  def take_grant_scopes do
    scopes = Process.get(@grant_scopes_key, MapSet.new())

    Process.delete(@grant_scopes_key)

    scopes
  end

  # Spells the given normalized query term as text, the way the client spells its own normalized
  # term of the same query (QuerySpelling.spell in query_spelling.mjs), so an answer the server
  # carries can be looked up by the query that gave it. The query holds every value it reads, so a
  # changed value is a changed spelling.
  #
  # The two terms aren't one shape, so neither is spelled as it stands. What's spelled is what both
  # hold: the term's fields but its source and trust, which a client term doesn't have, and every
  # value as the client holds it - an enum and a date as their wire text, and a boolean as its
  # text too, since an enum may declare true and the client holds that as a string. The attribute
  # a value is compared with tells what it is, so nothing two values spell alike can be confused.
  #
  # A filter is spelled with its clauses sorted by their spelling, all the way down, rather than
  # in the order the normalizer put them in: the two tiers' normalizers sort by different keys. A
  # number whole and within a JavaScript Number's exact range is spelled as an integer, since the
  # client holds 3 and 3.0 as one Number, any other float by its bits, and an integer past that
  # range in full, as the client spells the BigInt it holds one as.
  #
  # Every way the two could still differ has to make the spellings differ, never agree: a count
  # whose key misses is counted on the client, one whose key hits wrongly shows a number for
  # another query. So a shape this doesn't know is spelled by inspect/1 behind a mark the client
  # never writes. So is a term the client can't hold at all: a trusted one, whose answer reads past
  # the policies, and one with a source, which only an entity's derived field reads.
  @doc false
  @spec spell_query(Query.t()) :: String.t()
  def spell_query(%Query{source: nil, trust: false} = term) do
    spell_object([
      {"cardinality", spell_value(term.cardinality)},
      {"entity", spell_value(term.entity)},
      {"filter", spell_clauses(term.filter)},
      {"include", spell_include(term.include)},
      {"skip", spell_value(term.skip)},
      {"sort", spell_sort(term.sort)},
      {"take", spell_value(term.take)}
    ])
  end

  def spell_query(term), do: spell_unknown(term)

  # WARNING: must match the client's DataLayer.#carriedCount (data_layer.mjs).
  defp count_key(module, name, term) do
    "#{inspect(module)}/#{name}/#{spell_query(term)}"
  end

  defp entities(%NotIncluded{}), do: []

  defp entities(nil), do: []

  defp entities(results) when is_list(results), do: Enum.flat_map(results, &entities/1)

  defp entities(%entity_type{} = entity) do
    embedded =
      entity_type
      |> Entity.includable_names()
      |> Enum.flat_map(&entities(Map.fetch!(entity, &1)))

    [entity | embedded]
  end

  defp entities(_count), do: []

  defp gathered, do: Process.get(@key, %{})

  defp gathered_counts, do: Process.get(@counts_key, %{})

  # Ordered by id within each type, so that one render's rows are spelled the same way twice -
  # what a map hands its values over in follows the hashes of the keys.
  defp group(entities, actor_user_id) do
    entities
    |> Enum.group_by(&Codec.encode_enum_value(&1.__struct__))
    |> Map.new(fn {type_name, rows} ->
      {type_name,
       rows
       |> Enum.sort_by(& &1.id)
       |> Enum.map(&Frame.put_entity(&1, Frame.row_verdicts(actor_user_id, &1)).data)}
    end)
  end

  # One row can be reached from several props, and the same row twice is the same row - what
  # tells two apart is the pair of what they are and which one they are.
  defp key(%entity_type{id: id}), do: {entity_type, id}

  defp spell_alternatives(alternatives) do
    spelled_alternatives =
      alternatives
      |> Enum.map(&spell_clauses/1)
      |> Enum.sort()
      |> Enum.join(",")

    spell_object([{"or", "[#{spelled_alternatives}]"}])
  end

  defp spell_clause({:or, alternatives}) when is_list(alternatives) do
    if List.improper?(alternatives) do
      spell_unknown(alternatives)
    else
      spell_alternatives(alternatives)
    end
  end

  defp spell_clause({quantifier, {source, clauses}}) when quantifier in [:all, :any, :none] do
    spell_object([
      {"filter", spell_clauses(clauses)},
      {"quantifier", spell_value(quantifier)},
      {"source", spell_value(source)}
    ])
  end

  defp spell_clause({name, operator, operand}) when is_atom(operator) do
    "[#{spell_value(name)},#{spell_value(operator)},#{spell_value(operand)}]"
  end

  defp spell_clause(clause), do: spell_unknown(clause)

  defp spell_clause_list(clauses) do
    spelled_clauses =
      clauses
      |> Enum.map(&spell_clause/1)
      |> Enum.sort()
      |> Enum.join(",")

    "[#{spelled_clauses}]"
  end

  # WARNING: must match the client's QuerySpelling.#spellClauses (query_spelling.mjs).
  defp spell_clauses(clauses) when is_list(clauses) do
    if List.improper?(clauses) do
      spell_unknown(clauses)
    else
      spell_clause_list(clauses)
    end
  end

  defp spell_clauses(clauses), do: spell_unknown(clauses)

  defp spell_include(include) when is_map(include) and not is_struct(include) do
    names = Map.keys(include)

    if Enum.all?(names, &is_atom/1) do
      include
      |> Enum.map(fn
        {name, nil} -> {Atom.to_string(name), "null"}
        {name, sub_term} -> {Atom.to_string(name), spell_query(sub_term)}
      end)
      |> spell_object()
    else
      spell_unknown(include)
    end
  end

  defp spell_include(include), do: spell_unknown(include)

  # WARNING: must match the client's QuerySpelling.#spellNumber (query_spelling.mjs).
  defp spell_number(number) when is_integer(number), do: Integer.to_string(number)

  defp spell_number(number) when is_float(number) do
    if number == Float.round(number) and abs(number) <= @max_safe_integer do
      number
      |> trunc()
      |> Integer.to_string()
    else
      <<bits::binary-size(8)>> = <<number::float-64>>

      "float:#{Base.encode16(bits, case: :lower)}"
    end
  end

  # The members are named by plain strings, so they are sorted as they are written, and quoted the
  # way a string value is.
  #
  # WARNING: must match the client's QuerySpelling.#spellObject (query_spelling.mjs).
  defp spell_object(members) do
    spelled_members =
      members
      |> Enum.sort_by(fn {key, _spelled_value} -> key end)
      |> Enum.map_join(",", fn {key, spelled_value} -> "#{spell_string(key)}:#{spelled_value}" end)

    "{#{spelled_members}}"
  end

  defp spell_sort(sort) when is_list(sort) do
    if List.improper?(sort) do
      spell_unknown(sort)
    else
      spell_sort_entries(sort)
    end
  end

  defp spell_sort(sort), do: spell_unknown(sort)

  defp spell_sort_entries(sort) do
    spelled_entries =
      Enum.map_join(sort, ",", fn
        {name, direction} -> "[#{spell_value(name)},#{spell_value(direction)}]"
        entry -> spell_unknown(entry)
      end)

    "[#{spelled_entries}]"
  end

  # Only the quote and the backslash are escaped, which is all it takes to tell where a string
  # ends. The key travels in the page's JSON, which escapes everything else.
  #
  # WARNING: must match the client's QuerySpelling.#spellString (query_spelling.mjs).
  defp spell_string(text) do
    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    ~s("#{escaped}")
  end

  # Never what the client spells: what it spells starts with a quote, a bracket, a brace, a digit,
  # a minus, `float:`, `null` or the exclamation mark it marks its own unknown shapes with.
  defp spell_unknown(term), do: "?" <> inspect(term, limit: :infinity, printable_limit: :infinity)

  # A value as the client holds it once its stage has unboxed it (see Model.unbox in model.mjs),
  # read off the value's shape: a value has the shape of its attribute's type, since the stages
  # refuse one that doesn't. A name, a path and a quantifier's source are atoms and lists of them,
  # spelled as the client's strings and arrays of them.
  #
  # WARNING: must match the client's QuerySpelling.#spellValue (query_spelling.mjs).
  defp spell_value(nil), do: "null"

  defp spell_value(boolean) when is_boolean(boolean), do: spell_string(Atom.to_string(boolean))

  defp spell_value(atom) when is_atom(atom), do: spell_string(Codec.encode_enum_value(atom))

  defp spell_value(number) when is_number(number), do: spell_number(number)

  defp spell_value(text) when is_binary(text), do: spell_string(text)

  defp spell_value(%Date{} = date), do: spell_string(Codec.encode_json(date, :date))

  defp spell_value(%DateTime{} = datetime),
    do: spell_string(Codec.encode_json(datetime, :datetime))

  defp spell_value(%Time{} = time), do: spell_string(Codec.encode_json(time, :time))

  defp spell_value(list) when is_list(list) do
    if List.improper?(list) do
      spell_unknown(list)
    else
      "[#{Enum.map_join(list, ",", &spell_value/1)}]"
    end
  end

  defp spell_value({:attribute, name}), do: spell_object([{"attribute", spell_value(name)}])

  defp spell_value({:outer, levels, name}) when is_integer(levels) do
    spell_object([{"name", spell_value(name)}, {"outer", spell_number(levels)}])
  end

  defp spell_value(value), do: spell_unknown(value)
end
