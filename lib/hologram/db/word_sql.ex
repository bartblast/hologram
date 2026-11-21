defmodule Hologram.DB.WordSQL do
  @moduledoc false

  # What each query word computes, in SQL, over operands already rendered. A word's meaning lives
  # here and in Hologram.Query.Words, and the two have to agree on every value.

  @doc """
  Returns the SQL picking the given position, counting from 0, of the given text split by the given
  separator, nil past the end, as `String.split/2` then `Enum.at/2` do.

  PostgreSQL splits an empty string into no parts where Elixir gives one empty part, so an empty
  text is answered on its own. The position goes in as a literal, since PostgreSQL's arrays count
  from 1.
  """
  @spec at_split(String.t(), String.t(), non_neg_integer) :: String.t()
  def at_split(text, separator, position) do
    empty_text_part = if position == 0, do: "''::text", else: "NULL::text"

    "(CASE WHEN #{text} = '' THEN #{empty_text_part} " <>
      "ELSE (string_to_array(#{text}, #{separator}))[#{position + 1}] END)"
  end

  @doc """
  Returns the SQL of the first of the given values that isn't NULL.
  """
  @spec coalesce(list(String.t())) :: String.t()
  def coalesce(values), do: "COALESCE(#{Enum.join(values, ", ")})"

  @doc """
  Returns the SQL joining the given strings, NULL when any of them is.
  """
  @spec concat(list(String.t())) :: String.t()
  def concat(operands), do: "(#{Enum.join(operands, " || ")})"
end
