defmodule Hologram.Compiler.DataFlow.ShapeSet do
  @moduledoc false

  # A set of alternatives of a value (see Hologram.Compiler.DataFlow.shape/0). This module is the
  # one place that knows how such a set is stored, so the analysis never touches the representation.
  #
  # A set is an id in the store of its compile (see Hologram.Compiler.DataFlow.Store), which holds its
  # content once: the shapes, sorted in term order, without duplicates (an Erlang ordset), each shape
  # holding the ids of the sets nested in it. Two equal sets are one id, so a value that holds the same
  # piece many times holds its id, not copies: the analysis described values as trees before, and a
  # value that held its argument many times, put through a fold, grew to gigabytes of copies.
  #
  # Every function takes the store as its last argument, passed explicitly (the set is the subject,
  # so a pipeline of set functions reads as a pipeline). A set is always built by this module: every
  # result is interned, so equal content always gives the same id.
  #
  # A set holds one alternative per kind (see merged/2): two of a kind become one, the sets nested in
  # them joined, so a list of A or a list of B is a list of A or B. What the analysis does with a set
  # it does per alternative and joins the results, so the merge loses nothing; without it, answers
  # grew sideways, alternatives multiplying where their kinds were the same (M6: the big app's
  # compile 39% faster with the merge, the bundles the same).

  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Store

  # The id of the empty set: the store interns it first (see Store.start/1).
  @empty 1

  @type t :: pos_integer

  @doc """
  Returns whether the function returns true for every element of the set (true for an empty set).
  """
  @spec all?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def all?(set, fun, store), do: :lists.all(fun, Store.fetch(store, set))

  @doc """
  Returns whether the function returns true for some element of the set (false for an empty set).
  """
  @spec any?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def any?(set, fun, store), do: :lists.any(fun, Store.fetch(store, set))

  @doc """
  Returns whether the set has no elements.
  """
  @spec empty?(t, Store.t()) :: boolean
  def empty?(set, _store), do: set == @empty

  @doc """
  Returns the set of the elements for which the function returns true.
  """
  @spec filter(t, (DataFlow.shape() -> boolean), Store.t()) :: t
  def filter(set, fun, store) do
    Store.intern(store, :lists.filter(fun, Store.fetch(store, set)))
  end

  @doc """
  Returns the union of the sets the function returns for the elements.
  """
  @spec flat_map(t, (DataFlow.shape() -> t), Store.t()) :: t
  def flat_map(set, fun, store) do
    fun
    |> :lists.map(Store.fetch(store, set))
    |> union_all(store)
  end

  @doc """
  Returns the set that the given tree (see `Hologram.Compiler.DataFlow.tree/0`) stands for, its nested
  trees interned first.
  """
  @spec from_tree(DataFlow.tree(), Store.t()) :: t
  def from_tree(tree, store) do
    tree
    |> Enum.map(&DataFlow.map_nested(&1, fn nested -> from_tree(nested, store) end))
    |> new(store)
  end

  @doc """
  Returns the set of the shapes the function returns for the elements.
  """
  @spec map(t, (DataFlow.shape() -> DataFlow.shape()), Store.t()) :: t
  def map(set, fun, store) do
    fun
    |> :lists.map(Store.fetch(store, set))
    |> new(store)
  end

  @doc """
  Returns whether the shape is an element of the set.
  """
  @spec member?(t, DataFlow.shape(), Store.t()) :: boolean
  def member?(set, shape, store), do: :ordsets.is_element(shape, Store.fetch(store, set))

  @doc """
  Returns an empty set.
  """
  @spec new(Store.t()) :: t
  def new(_store), do: @empty

  @doc """
  Returns the set of the given shapes, each once.
  """
  @spec new([DataFlow.shape()], Store.t()) :: t
  def new(shapes, store), do: intern(:lists.usort(shapes), store)

  @doc """
  Returns the set with the shape added.
  """
  @spec put(t, DataFlow.shape(), Store.t()) :: t
  def put(set, shape, store) do
    intern(:ordsets.add_element(shape, Store.fetch(store, set)), store)
  end

  @doc """
  Folds the elements of the set in term order, starting with the given accumulator.
  """
  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc), Store.t()) :: acc when acc: term
  def reduce(set, acc, fun, store), do: :lists.foldl(fun, acc, Store.fetch(store, set))

  @doc """
  Returns the number of elements of the set.
  """
  @spec size(t, Store.t()) :: non_neg_integer
  def size(set, store), do: length(Store.fetch(store, set))

  @doc """
  Returns the elements of the set in term order, their nested sets ids.
  """
  @spec to_list(t, Store.t()) :: [DataFlow.shape()]
  def to_list(set, store), do: Store.fetch(store, set)

  @doc """
  Returns the elements of both sets, once each, alternatives of a kind merged. Remembered per pair of
  sets: merging joins the sets nested in the alternatives, so a set shared by many values would be
  joined again on every path to it.
  """
  @spec union(t, t, Store.t()) :: t
  def union(set, set, _store), do: set

  def union(set_1, set_2, store) do
    Store.memo(store, {:union, min(set_1, set_2), max(set_1, set_2)}, fn ->
      intern(:ordsets.union(Store.fetch(store, set_1), Store.fetch(store, set_2)), store)
    end)
  end

  @doc """
  Returns the elements of every given set, once each, alternatives of a kind merged; remembered as
  `union/3` is.
  """
  @spec union_all([t], Store.t()) :: t
  def union_all(sets, store) do
    case :lists.usort(sets) do
      [] ->
        @empty

      [set] ->
        set

      distinct ->
        Store.memo(store, {:union_all, distinct}, fn ->
          intern(:ordsets.union(Enum.map(distinct, &Store.fetch(store, &1))), store)
        end)
    end
  end

  # The id of the content, its alternatives of a kind merged first (see merged/2).
  defp intern(content, store), do: Store.intern(store, merged(content, store))

  # What makes two alternatives of a kind: the kind of a list, a bag or a step into a value not known
  # yet; the name of a dot; the ref of an anonymous function; the module of a struct; being a map; a
  # tuple's size and tag (see tuple_tag/2); the number of arguments of a call of a function value, the
  # name and arity of a dynamic call, the rules module and name of a rule shape. Any other shape is a
  # kind of its own.
  #
  # Calls merged stand for every function or module with every argument (`m1.f(a)` or `m2.f(b)` is
  # `(m1 or m2).f(a or b)`), which can give types neither call gives when two modules not known yet
  # get crossed with each other's arguments; calls of one callee lose nothing, since an answer is
  # built from each argument on its own. Kept apart, calls like these filled page helpers' answers
  # past the cap (M6: 26 functions too large to flatten apart, 4 merged).
  defp kind_key({kind, _set}, _store) when kind in [:as_map, :bag, :contents, :list, :part],
    do: kind

  defp kind_key({:dot, _set, name}, _store), do: {:dot, name}

  defp kind_key({:fun, ref, _returned}, _store), do: {:fun, ref}

  defp kind_key({:struct, module, _fields}, _store), do: {:struct, module}

  defp kind_key({:map, _fields}, _store), do: :map

  defp kind_key({:tuple, elements}, store),
    do: {:tuple, length(elements), tuple_tag(elements, store)}

  defp kind_key({:call, _fun, args}, _store), do: {:call, length(args)}

  defp kind_key({:dyn, _module, name, arity, _args}, _store), do: {:dyn, name, arity}

  defp kind_key({:rule, rules_module, name, _args}, _store), do: {:rule, rules_module, name}

  defp kind_key(shape, _store), do: {:one, shape}

  # Two alternatives of a kind (see kind_key/2) as one, the sets nested in them joined; a struct's or a
  # map's fields key by key (see merge_fields/3); a tuple's elements, and a call's arguments, position
  # by position (see union_each/3).
  defp merge({kind, set_1}, {kind, set_2}, store)
       when kind in [:as_map, :bag, :contents, :list, :part],
       do: {kind, union(set_1, set_2, store)}

  defp merge({:dot, set_1, name}, {:dot, set_2, name}, store),
    do: {:dot, union(set_1, set_2, store), name}

  defp merge({:fun, ref, set_1}, {:fun, ref, set_2}, store),
    do: {:fun, ref, union(set_1, set_2, store)}

  defp merge({:struct, module, fields_1}, {:struct, module, fields_2}, store),
    do: {:struct, module, merge_fields(fields_1, fields_2, store)}

  defp merge({:map, fields_1}, {:map, fields_2}, store),
    do: {:map, merge_fields(fields_1, fields_2, store)}

  defp merge({:tuple, elements_1}, {:tuple, elements_2}, store),
    do: {:tuple, union_each(elements_1, elements_2, store)}

  defp merge({:call, fun_1, args_1}, {:call, fun_2, args_2}, store),
    do: {:call, union(fun_1, fun_2, store), union_each(args_1, args_2, store)}

  defp merge({:dyn, module_1, name, arity, args_1}, {:dyn, module_2, name, arity, args_2}, store) do
    {:dyn, union(module_1, module_2, store), name, arity, union_each(args_1, args_2, store)}
  end

  defp merge({:rule, rules_module, name, args_1}, {:rule, rules_module, name, args_2}, store),
    do: {:rule, rules_module, name, union_each(args_1, args_2, store)}

  # Two structs' or maps' fields as one (see Hologram.Compiler.DataFlow.fields/0): a key both have
  # holds the join of the two, a key one has holds what it holds there, the rest key like any other.
  # Which field value went with which is lost (`%S{a: X, b: 1}` or `%S{a: 1, b: Y}` is
  # `%S{a: X or 1, b: 1 or Y}`), and no question the analysis answers depends on it.
  defp merge_fields(fields_1, fields_2, store) do
    Map.merge(fields_1, fields_2, fn _key, set_1, set_2 -> union(set_1, set_2, store) end)
  end

  # The content (a sorted list of shapes) with its alternatives of a kind merged, sorted. A content
  # with no two of a kind, the common case, is given back as it is.
  defp merged([_shape_1, _shape_2 | _shapes] = content, store) do
    groups = Enum.group_by(content, &kind_key(&1, store))

    if map_size(groups) == length(content) do
      content
    else
      groups
      |> Map.values()
      |> Enum.map(fn [first | rest] -> Enum.reduce(rest, first, &merge(&2, &1, store)) end)
      |> :lists.usort()
    end
  end

  defp merged(content, _store), do: content

  # The tag of a tuple of the given elements: its first element when that is a single atom (`:ok` in
  # `{:ok, value}`), which patterns choose on, so tuples of different tags stay apart; `:none` for any
  # other tuple (untagged tuples of a size merge: a pattern choosing on a later element of one then
  # takes the others' too, the same loss as a struct's fields merged).
  defp tuple_tag([first | _rest], store) do
    case Store.fetch(store, first) do
      [{:atom, atom}] -> atom
      _other -> :none
    end
  end

  defp tuple_tag([], _store), do: :none

  # The given lists of sets joined position by position.
  defp union_each(sets_1, sets_2, store), do: Enum.zip_with(sets_1, sets_2, &union(&1, &2, store))
end
