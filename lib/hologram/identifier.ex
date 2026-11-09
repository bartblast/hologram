defmodule Hologram.Identifier do
  @moduledoc false

  # An identifier names something, like a channel or a key: an atom, or a tuple of an atom followed
  # by one or more integers, strings or atoms. None of its atoms is nil, true or false, and its
  # strings are valid UTF-8.

  @reserved_atom_hint "nil, true and false can't be in an identifier"

  @reserved_atoms [nil, true, false]

  @doc """
  Checks whether the given value is an identifier.

  Returns `:ok`, or `{:error, hint}`, where the hint says why the value isn't one, or is `nil` when
  the value isn't shaped like one at all. The first problem found decides the hint: the tuple's
  size, then its first element, then the elements after it, from left to right.
  """
  @spec check(any) :: :ok | {:error, String.t() | nil}
  def check(value) when value in @reserved_atoms, do: {:error, @reserved_atom_hint}

  def check(value) when is_atom(value), do: :ok

  def check(value) when is_tuple(value) and tuple_size(value) < 2 do
    {:error, "an identifier tuple holds an atom and at least one more value"}
  end

  def check(value) when is_tuple(value) do
    [tag | rest] = Tuple.to_list(value)

    cond do
      tag in @reserved_atoms -> {:error, @reserved_atom_hint}
      not is_atom(tag) -> {:error, "an identifier tuple starts with an atom"}
      true -> check_values(rest)
    end
  end

  def check(_value), do: {:error, nil}

  @doc """
  Builds the message of an error raised for a value that isn't what was expected, in the format
  shared by everything that takes an identifier.

  ## Examples

      iex> message("a channel must be an identifier", {:room, nil}, "nil, true and false can't be in an identifier")
      "a channel must be an identifier, got: {:room, nil} - nil, true and false can't be in an identifier"
  """
  @spec message(String.t(), any, String.t() | nil) :: String.t()
  def message(expectation, value, hint)

  def message(expectation, value, nil), do: "#{expectation}, got: #{inspect(value)}"

  def message(expectation, value, hint), do: "#{expectation}, got: #{inspect(value)} - #{hint}"

  @doc """
  Returns the given value if it's an identifier, or raises `ArgumentError` whose message starts
  with the given expectation.
  """
  @spec validate!(any, String.t()) :: atom | tuple
  def validate!(value, expectation) do
    case check(value) do
      :ok -> value
      {:error, hint} -> raise ArgumentError, message: message(expectation, value, hint)
    end
  end

  defp check_values(values) do
    Enum.find_value(values, :ok, fn value ->
      case value_hint(value) do
        nil -> nil
        hint -> {:error, hint}
      end
    end)
  end

  # Why a value after an identifier tuple's atom can't be there, or nil when it can.
  defp value_hint(value) when value in @reserved_atoms, do: @reserved_atom_hint

  defp value_hint(value) when is_atom(value) or is_integer(value), do: nil

  defp value_hint(value) when is_binary(value) do
    unless String.valid?(value), do: "strings must be valid UTF-8"
  end

  defp value_hint(_value),
    do: "an identifier tuple holds only integers, strings and atoms after its atom"
end
