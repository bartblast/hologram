defmodule Hologram.Template.DataTransfer do
  @moduledoc false

  alias Hologram.Commons.KernelUtils
  alias Hologram.Identifier

  # What the $data_transfer attribute takes, judged by the build for a literal value and by the
  # server renderer for the value the attribute renders with, so both refuse a value with the same
  # message.
  #
  # Values are inspected with their maps sorted, so a message reads the same on the server and the
  # client, whatever order a map's keys come in.
  #
  # WARNING: must match the client renderer's #dataTransferEntries, #renderDataTransfer,
  # #renderDragData, #renderDragImage, #renderDropEffect and #renderEffectsAllowed (renderer.mjs).

  defmodule Unknown do
    @moduledoc false

    # A value in a $data_transfer literal that only the render knows, like an assign.
    defstruct []

    @type t :: %__MODULE__{}
  end

  @drop_effects [:none, :copy, :move, :link]

  @effects_allowed [:copy, :move, :link]

  @image_keys [:ref, :x, :y]

  @keys [:data, :drop_effect, :effects_allowed, :image]

  @doc """
  Judges a $data_transfer value on the given tag: a keyword list or a map of the keys the
  attribute takes, each given once, with a drop effect only on a tag with a $drop binding, and
  data, allowed effects and a drag image only on an element, where a drag can start. A map's
  entries are judged in the order of their keys, a keyword list's in the order written.

  The tag is "window" or "document" for those tags, nil for an element, and `%Unknown{}` for a
  dynamic tag, which stops the judging at data, allowed effects or a drag image, since only the
  render knows whether the tag is an element. A `%Unknown{}` value stops the judging too, since
  what comes after it depends on what it turns out to be. Returns `:ok`, or `{:error, message}`.
  """
  @spec check(any, boolean, String.t() | nil | Unknown.t()) :: :ok | {:error, String.t()}
  def check(value, has_drop?, tag) do
    with {:ok, entries} <- entries(value) do
      check_entries(entries, has_drop?, tag)
    end
  end

  defp check_entries([], _has_drop?, _tag), do: :ok

  defp check_entries([{key, value} | rest], has_drop?, tag) do
    cond do
      key not in @keys ->
        {:error,
         "the $data_transfer attribute takes the :data, :drop_effect, :effects_allowed and :image keys, got #{KernelUtils.inspect(key)}"}

      key != :drop_effect and match?(%Unknown{}, tag) ->
        :ok

      key != :drop_effect and tag != nil ->
        {:error,
         "the $data_transfer #{key} goes on the element a drag starts from, so a <#{tag}> tag can't take it"}

      match?(%Unknown{}, value) ->
        :ok

      true ->
        with :ok <- check_entry(key, value, has_drop?) do
          check_entries(rest, has_drop?, tag)
        end
    end
  end

  defp check_entry(:data, value, _has_drop?) do
    if drag_data?(value) do
      :ok
    else
      {:error,
       ~s'the $data_transfer data takes a map of drag data types to strings or nil, like %{"text/plain" => "Buy milk"}, got #{KernelUtils.inspect(value)}'}
    end
  end

  defp check_entry(:drop_effect, value, has_drop?) do
    cond do
      value not in @drop_effects ->
        {:error,
         "the $data_transfer drop_effect takes :none, :copy, :move or :link, got #{KernelUtils.inspect(value)}"}

      not has_drop? ->
        {:error,
         "the $data_transfer drop_effect goes on a tag with a $drop binding, which makes it a drop target"}

      true ->
        :ok
    end
  end

  defp check_entry(:effects_allowed, value, _has_drop?) do
    if effects_allowed?(value) do
      :ok
    else
      {:error,
       "the $data_transfer effects_allowed takes :copy, :move or :link, or a list of them, got #{KernelUtils.inspect(value)}"}
    end
  end

  defp check_entry(:image, value, _has_drop?) do
    if drag_image?(value) do
      :ok
    else
      {:error,
       "the $data_transfer image takes a map with a ref and optional integer x and y offsets, like %{ref: :task_preview, x: 16, y: 16}, got #{KernelUtils.inspect(value)}"}
    end
  end

  defp drag_data?(%_struct{}), do: false

  defp drag_data?(value) when is_map(value) do
    Enum.all?(value, fn {type, type_value} ->
      text?(type) and (is_nil(type_value) or text?(type_value))
    end)
  end

  defp drag_data?(_value), do: false

  defp drag_image?(%_struct{}), do: false

  defp drag_image?(%{ref: ref} = value) do
    value
    |> Map.keys()
    |> Enum.all?(&(&1 in @image_keys)) and
      (is_nil(ref) or Identifier.check(ref) == :ok) and
      Enum.all?([:x, :y], &(not Map.has_key?(value, &1) or is_integer(value[&1])))
  end

  defp drag_image?(_value), do: false

  defp duplicate_key(keys) do
    Enum.reduce_while(keys, MapSet.new(), fn key, seen_keys ->
      if MapSet.member?(seen_keys, key) do
        {:halt, {:duplicate, key}}
      else
        {:cont, MapSet.put(seen_keys, key)}
      end
    end)
  end

  defp effects_allowed?(effects) when is_list(effects) do
    not List.improper?(effects) and Enum.all?(effects, &(&1 in @effects_allowed))
  end

  defp effects_allowed?(effect), do: effect in @effects_allowed

  defp entries(%_struct{} = value), do: invalid_value_error(value)

  defp entries(value) when is_map(value) do
    entries =
      value
      |> Map.to_list()
      |> List.keysort(0)

    {:ok, entries}
  end

  defp entries(value) when is_list(value) do
    if Keyword.keyword?(value) do
      case value
           |> Keyword.keys()
           |> duplicate_key() do
        {:duplicate, key} ->
          {:error,
           "the $data_transfer attribute takes each key once, but got the #{KernelUtils.inspect(key)} key twice"}

        _seen_keys ->
          {:ok, value}
      end
    else
      invalid_value_error(value)
    end
  end

  defp entries(value), do: invalid_value_error(value)

  defp invalid_value_error(value) do
    {:error,
     "the $data_transfer attribute takes a keyword list or a map, got #{KernelUtils.inspect(value)}"}
  end

  defp text?(value), do: is_binary(value) and String.valid?(value)
end
