defmodule Hologram.Entity.Validator do
  @moduledoc false

  alias Hologram.Commons.Types, as: T

  # Postgres int8 column bounds
  @max_integer 9_223_372_036_854_775_807
  @min_integer -9_223_372_036_854_775_808

  @doc """
  Returns true if the given value is a valid value for the given attribute type and declaration options, or false otherwise.
  A nil value is valid only when the optional option is true.
  """
  @spec attr_value_valid?(any, atom, T.opts()) :: boolean
  def attr_value_valid?(value, type, opts \\ [])

  def attr_value_valid?(nil, _type, opts), do: Keyword.get(opts, :optional) == true

  def attr_value_valid?(value, :boolean, _opts), do: is_boolean(value)

  def attr_value_valid?(value, :date, _opts), do: is_struct(value, Date)

  def attr_value_valid?(value, :datetime, _opts), do: is_struct(value, DateTime)

  def attr_value_valid?(value, :enum, opts),
    do: is_atom(value) and value in Keyword.fetch!(opts, :values)

  def attr_value_valid?(value, :float, _opts), do: is_float(value)

  def attr_value_valid?(value, :integer, _opts) do
    is_integer(value) and value >= @min_integer and value <= @max_integer
  end

  def attr_value_valid?(value, :string, _opts), do: is_binary(value) and String.valid?(value)
end
