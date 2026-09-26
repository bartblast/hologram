defmodule Hologram.Compiler.DataFlow.Models do
  @moduledoc false

  # Hand-written summaries of functions (see Hologram.Compiler.DataFlow.summary/2), which the
  # analysis takes instead of following their code: Erlang functions have no IR, and some Elixir
  # functions are worth not following. A model says that a function returns a value holding no
  # types (:prim), never returns (it raises, throws or exits), or returns what it is given, in the
  # shapes of Hologram.Compiler.DataFlow over its params: `{:contents, ...}` for what is inside an
  # argument, `{:call, ...}` for what calling a function argument gives. A function without a model
  # is followed through its code, or returns everything it is given when it has none.
  #
  # A model must not be smaller than what the function can return.

  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.ShapeSet

  # Erlang functions that never return.
  @diverging_mfas [
    {:erlang, :error, 1},
    {:erlang, :error, 2},
    {:erlang, :error, 3},
    {:erlang, :exit, 1},
    {:erlang, :halt, 0},
    {:erlang, :halt, 1},
    {:erlang, :halt, 2},
    {:erlang, :nif_error, 1},
    {:erlang, :nif_error, 2},
    {:erlang, :raise, 3},
    {:erlang, :throw, 1}
  ]

  # Functions of :erlang whose result holds no types, whatever their arity. Their results are
  # numbers, booleans, binaries, charlists, atoms the code does not name, references, pids, or values
  # from outside the code (the process dictionary, a term decoded from a binary).
  @primitive_erlang_functions [
    :*,
    :+,
    :-,
    :/,
    :"/=",
    :<,
    :"=/=",
    :"=:=",
    :"=<",
    :==,
    :>,
    :>=,
    :abs,
    :and,
    :atom_to_binary,
    :atom_to_list,
    :band,
    :binary_part,
    :binary_to_atom,
    :binary_to_existing_atom,
    :binary_to_float,
    :binary_to_integer,
    :binary_to_list,
    :binary_to_term,
    :bit_size,
    :bnot,
    :bor,
    :bsl,
    :bsr,
    :bxor,
    :byte_size,
    :ceil,
    :div,
    :float,
    :float_to_binary,
    :float_to_list,
    :floor,
    :get,
    :integer_to_binary,
    :integer_to_list,
    :iolist_size,
    :iolist_to_binary,
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_function,
    :is_integer,
    :is_list,
    :is_map,
    :is_map_key,
    :is_number,
    :is_pid,
    :is_port,
    :is_record,
    :is_reference,
    :is_tuple,
    :length,
    :list_to_atom,
    :list_to_binary,
    :list_to_existing_atom,
    :list_to_float,
    :list_to_integer,
    :make_ref,
    :map_size,
    :monotonic_time,
    :node,
    :not,
    :or,
    :phash2,
    :put,
    :rem,
    :round,
    :self,
    :size,
    :system_time,
    :term_to_binary,
    :trunc,
    :tuple_size,
    :unique_integer,
    :xor
  ]

  # Elixir functions whose result holds no types. A protocol function listed here (String.Chars,
  # List.Chars, Inspect) is taken at its word: every implementation returns a binary or a charlist.
  @primitive_mfas [
    {Atom, :to_charlist, 1},
    {Atom, :to_string, 1},
    {Calendar, :strftime, 2},
    {Calendar, :strftime, 3},
    {Date, :to_iso8601, 1},
    {Date, :to_iso8601, 2},
    {Date, :to_string, 1},
    {DateTime, :to_iso8601, 1},
    {DateTime, :to_iso8601, 2},
    {DateTime, :to_iso8601, 3},
    {DateTime, :to_string, 1},
    {Enum, :all?, 1},
    {Enum, :all?, 2},
    {Enum, :any?, 1},
    {Enum, :any?, 2},
    {Enum, :count, 1},
    {Enum, :count, 2},
    {Enum, :empty?, 1},
    {Enum, :find_index, 2},
    {Enum, :join, 1},
    {Enum, :join, 2},
    {Enum, :map_join, 2},
    {Enum, :map_join, 3},
    {Enum, :member?, 2},
    {Enum, :product, 1},
    {Enum, :sum, 1},
    {Inspect, :inspect, 2},
    {Inspect.Algebra, :format, 2},
    {Jason, :encode!, 1},
    {Jason, :encode!, 2},
    {Kernel, :inspect, 1},
    {Kernel, :inspect, 2},
    {Keyword, :has_key?, 2},
    {List.Chars, :to_charlist, 1},
    {Map, :has_key?, 2},
    {NaiveDateTime, :to_iso8601, 1},
    {NaiveDateTime, :to_iso8601, 2},
    {NaiveDateTime, :to_string, 1},
    {String.Chars, :to_string, 1},
    {Time, :to_iso8601, 1},
    {Time, :to_iso8601, 2},
    {Time, :to_string, 1},
    {URI, :encode, 1},
    {URI, :encode, 2},
    {URI, :encode_query, 1},
    {URI, :encode_query, 2},
    {URI, :encode_www_form, 1}
  ]

  # Modules whose every function's result holds no types: text, numbers, bits, hashes and parsing.
  @primitive_modules [
    :base64,
    :binary,
    :crypto,
    :filename,
    :io_lib,
    :math,
    :rand,
    :re,
    :string,
    :unicode,
    Base,
    Bitwise,
    Float,
    Integer,
    String
  ]

  # Functions that return their first argument, the server or the component, as it was: what they
  # are given is a key, a status, a page to redirect to, a response, a user id or a channel, which
  # holds no type the client needs. A value put in the session, a cookie or the stash is not dropped
  # this way: another handler can read it back and hand it to the client, so the code of those
  # functions is followed, and the value stays in the server struct they return.
  @unchanged_first_arg_mfas [
    {Hologram.Component, :delete_subscription, 2},
    {Hologram.Component, :put_subscription, 2},
    {Hologram.Server, :delete_cookie, 2},
    {Hologram.Server, :delete_session, 2},
    {Hologram.Server, :delete_stash, 2},
    {Hologram.Server, :put_redirect, 2},
    {Hologram.Server, :put_redirect, 3},
    {Hologram.Server, :put_response_body, 2},
    {Hologram.Server, :put_response_header, 3},
    {Hologram.Server, :put_status, 2},
    {Hologram.Server, :put_user_id, 2}
  ]

  @doc """
  Returns the Elixir functions listed one by one (not through their module), as MFAs.
  """
  @spec listed_elixir_mfas :: [mfa]
  def listed_elixir_mfas, do: @primitive_mfas ++ @unchanged_first_arg_mfas

  @doc """
  Returns the model of the given function: the shapes of what it returns, or nil when it has none.
  """
  @spec summary(mfa) :: DataFlow.shapes() | nil
  def summary({module, function, _arity} = mfa) do
    cond do
      mfa in @diverging_mfas -> ShapeSet.new()
      module == :erlang and function in @primitive_erlang_functions -> prim()
      module in @primitive_modules or mfa in @primitive_mfas -> prim()
      mfa in @unchanged_first_arg_mfas -> param(0)
      true -> structural(mfa)
    end
  end

  defp atom(value), do: ShapeSet.new([{:atom, value}])

  defp bag(shapes), do: ShapeSet.new([{:bag, shapes}])

  defp call(fun, args), do: ShapeSet.new([{:call, fun, args}])

  defp contents(shapes), do: ShapeSet.new([{:contents, shapes}])

  # What folding the function over the elements gives, from the accumulator: two rounds of calling
  # the function with the args the given function builds around what the rounds before gave. The
  # types that can reach the accumulator are all there after one round; the second keeps a value
  # one round deeper.
  defp fold(fun, acc, args_around) do
    round_1 = union([acc, call(fun, args_around.(acc))])
    union([round_1, call(fun, args_around.(round_1))])
  end

  defp list(elements), do: ShapeSet.new([{:list, elements}])

  defp map(inner), do: ShapeSet.new([{:map, inner}])

  # What :lists.mapfoldl/3 and :lists.mapfoldr/3 give: the mapped elements and the accumulator,
  # from two rounds of calling the function, which returns a tuple of both.
  defp mapfold do
    round_1 = call(param(0), [contents(param(2)), param(1)])
    acc_1 = union([param(1), contents(round_1)])
    round_2 = call(param(0), [contents(param(2)), acc_1])
    acc_2 = union([acc_1, contents(round_2)])
    mapped = contents(union([round_1, round_2]))

    tuple([list(mapped), acc_2])
  end

  defp param(index), do: ShapeSet.new([{:param, index}])

  defp part(shapes), do: ShapeSet.new([{:part, shapes}])

  defp prim, do: ShapeSet.new([:prim])

  defp structural({:erlang, :++, 2}), do: list(union([contents(param(0)), contents(param(1))]))
  defp structural({:erlang, :--, 2}), do: param(0)
  defp structural({:erlang, :append_element, 2}), do: bag(union([contents(param(0)), param(1)]))
  defp structural({:erlang, :element, 2}), do: contents(param(1))
  defp structural({:erlang, :hd, 1}), do: contents(param(0))
  defp structural({:erlang, :list_to_tuple, 1}), do: bag(contents(param(0)))
  defp structural({:erlang, :max, 2}), do: union([param(0), param(1)])
  defp structural({:erlang, :min, 2}), do: union([param(0), param(1)])
  defp structural({:erlang, :setelement, 3}), do: bag(union([contents(param(1)), param(2)]))
  defp structural({:erlang, :tl, 1}), do: param(0)
  defp structural({:erlang, :tuple_to_list, 1}), do: list(contents(param(0)))

  defp structural({:lists, function, 1})
       when function in [:droplast, :reverse, :sort, :uniq, :usort],
       do: param(0)

  defp structural({:lists, function, 2})
       when function in [
              :delete,
              :dropwhile,
              :filter,
              :keysort,
              :nthtail,
              :sort,
              :takewhile,
              :uniq,
              :usort
            ],
       do: param(1)

  defp structural({:lists, function, 2}) when function in [:all, :any, :member, :seq], do: prim()
  defp structural({:lists, function, 3}) when function in [:keymember, :seq], do: prim()
  defp structural({:lists, :sum, 1}), do: prim()
  defp structural({:lists, :append, 1}), do: list(contents(contents(param(0))))
  defp structural({:lists, :append, 2}), do: list(union([contents(param(0)), contents(param(1))]))
  defp structural({:lists, :duplicate, 2}), do: list(param(1))
  defp structural({:lists, :enumerate, 1}), do: list(tuple([prim(), contents(param(0))]))

  defp structural({:lists, :filtermap, 2}) do
    kept = call(param(0), [contents(param(1))])
    list(union([contents(param(1)), contents(kept)]))
  end

  defp structural({:lists, :flatmap, 2}), do: list(contents(call(param(0), [contents(param(1))])))
  defp structural({:lists, :flatten, 1}), do: list(part(param(0)))
  defp structural({:lists, :flatten, 2}), do: list(union([part(param(0)), contents(param(1))]))
  defp structural({:lists, :foldl, 3}), do: fold(param(0), param(1), &[contents(param(2)), &1])
  defp structural({:lists, :foldr, 3}), do: fold(param(0), param(1), &[contents(param(2)), &1])
  defp structural({:lists, :foreach, 2}), do: atom(:ok)
  defp structural({:lists, :keydelete, 3}), do: param(2)
  defp structural({:lists, :keyfind, 3}), do: union([contents(param(2)), atom(false)])
  defp structural({:lists, :keyreplace, 4}), do: list(union([contents(param(2)), param(3)]))
  defp structural({:lists, :keystore, 4}), do: list(union([contents(param(2)), param(3)]))

  defp structural({:lists, :keytake, 3}) do
    union([tuple([atom(:value), contents(param(2)), param(2)]), atom(false)])
  end

  defp structural({:lists, :last, 1}), do: contents(param(0))
  defp structural({:lists, :map, 2}), do: list(call(param(0), [contents(param(1))]))
  defp structural({:lists, :mapfoldl, 3}), do: mapfold()
  defp structural({:lists, :mapfoldr, 3}), do: mapfold()
  defp structural({:lists, :max, 1}), do: contents(param(0))
  defp structural({:lists, :min, 1}), do: contents(param(0))
  defp structural({:lists, :nth, 2}), do: contents(param(1))
  defp structural({:lists, :partition, 2}), do: tuple([param(1), param(1)])

  defp structural({:lists, :search, 2}) do
    union([tuple([atom(:value), contents(param(1))]), atom(false)])
  end

  defp structural({:lists, :split, 2}), do: tuple([param(1), param(1)])
  defp structural({:lists, :splitwith, 2}), do: tuple([param(1), param(1)])
  defp structural({:lists, :sublist, arity}) when arity in [2, 3], do: param(0)

  defp structural({:lists, :unzip, 1}) do
    elements = list(contents(contents(param(0))))
    tuple([elements, elements])
  end

  defp structural({:lists, :zip, 2}), do: list(tuple([contents(param(0)), contents(param(1))]))

  defp structural({:maps, :filter, 2}), do: map(contents(param(1)))

  defp structural({:maps, :find, 2}) do
    union([tuple([atom(:ok), contents(param(1))]), atom(:error)])
  end

  defp structural({:maps, :fold, 3}) do
    fold(param(0), param(1), &[contents(param(2)), contents(param(2)), &1])
  end

  defp structural({:maps, :from_keys, 2}), do: map(union([contents(param(0)), param(1)]))
  defp structural({:maps, :from_list, 1}), do: map(contents(contents(param(0))))
  defp structural({:maps, :get, 2}), do: contents(param(1))
  defp structural({:maps, :get, 3}), do: union([contents(param(1)), param(2)])
  defp structural({:maps, :is_key, 2}), do: prim()
  defp structural({:maps, :keys, 1}), do: list(contents(param(0)))

  defp structural({:maps, :map, 2}) do
    values = contents(param(1))
    map(union([values, call(param(0), [values, values])]))
  end

  defp structural({:maps, :merge, 2}), do: map(union([contents(param(0)), contents(param(1))]))

  defp structural({:maps, :merge_with, 3}) do
    values = union([contents(param(1)), contents(param(2))])
    map(union([values, call(param(0), [values, values, values])]))
  end

  defp structural({:maps, :new, 0}), do: map(ShapeSet.new())
  defp structural({:maps, :put, 3}), do: map(union([param(0), param(1), contents(param(2))]))
  defp structural({:maps, :remove, 2}), do: map(contents(param(1)))
  defp structural({:maps, :size, 1}), do: prim()

  defp structural({:maps, :take, 2}) do
    union([tuple([contents(param(1)), map(contents(param(1)))]), atom(:error)])
  end

  defp structural({:maps, :to_list, 1}) do
    inner = contents(param(0))
    list(tuple([inner, inner]))
  end

  defp structural({:maps, :update, 3}), do: map(union([param(0), param(1), contents(param(2))]))

  defp structural({:maps, :update_with, 3}) do
    values = contents(param(2))
    map(union([param(0), values, call(param(1), [values])]))
  end

  defp structural({:maps, :update_with, 4}) do
    values = contents(param(3))
    map(union([param(0), param(2), values, call(param(1), [values])]))
  end

  defp structural({:maps, :values, 1}), do: list(contents(param(0)))
  defp structural({:maps, :with, 2}), do: map(contents(param(1)))
  defp structural({:maps, :without, 2}), do: map(contents(param(1)))

  defp structural(_mfa), do: nil

  defp tuple(elements), do: ShapeSet.new([{:tuple, elements}])

  defp union(sets), do: ShapeSet.union_all(sets)
end
