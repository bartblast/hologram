defmodule Hologram.Compiler.DataFlow.Models do
  @moduledoc false

  # Hand-written summaries of functions (see Hologram.Compiler.DataFlow.summary/2), which the
  # analysis takes instead of following their code: Erlang functions have no IR, and some Elixir
  # functions are worth not following. A function listed here returns a value holding no types
  # (:prim) or never returns (it raises, throws or exits). A function not listed has no model.
  #
  # A model must not be smaller than what the function can return: a function whose result can hold
  # a struct, a module atom or a function given to it is not listed here.

  alias Hologram.Compiler.DataFlow

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

  @doc """
  Returns the Elixir functions listed one by one (not through their module), as MFAs.
  """
  @spec listed_elixir_mfas :: [mfa]
  def listed_elixir_mfas, do: @primitive_mfas

  @doc """
  Returns the model of the given function: the shapes of what it returns, or nil when it has none.
  """
  @spec summary(mfa) :: DataFlow.shapes() | nil
  def summary({module, function, _arity} = mfa) do
    cond do
      mfa in @diverging_mfas -> MapSet.new()
      module == :erlang and function in @primitive_erlang_functions -> MapSet.new([:prim])
      module in @primitive_modules or mfa in @primitive_mfas -> MapSet.new([:prim])
      true -> nil
    end
  end
end
