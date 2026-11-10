defmodule Hologram.Template.DataTransfer do
  @moduledoc false

  # What the $data_transfer attribute takes, and the messages that refuse anything else, which the
  # server renderer uses to judge the value the attribute renders with.
  #
  # WARNING: the messages must match the client renderer's (renderer.mjs).

  @drop_effects [:none, :copy, :move, :link]

  @doc """
  Returns the drop effects the drop_effect key takes.
  """
  @spec drop_effects :: list(atom)
  def drop_effects, do: @drop_effects

  @doc """
  Returns the message for a drop_effect key on a tag with no $drop binding.
  """
  @spec drop_effect_without_drop_message :: String.t()
  def drop_effect_without_drop_message do
    "the $data_transfer drop_effect goes on a tag with a $drop binding, which makes it a drop target"
  end

  @doc """
  Returns the message for a key given twice.
  """
  @spec duplicate_key_message(atom) :: String.t()
  def duplicate_key_message(key) do
    "the $data_transfer attribute takes each key once, but got the #{inspect(key)} key twice"
  end

  @doc """
  Returns the message for a drop_effect value outside the drop effects, given as the text that
  shows it.
  """
  @spec invalid_drop_effect_message(String.t()) :: String.t()
  def invalid_drop_effect_message(value_text) do
    "the $data_transfer drop_effect takes :none, :copy, :move or :link, got #{value_text}"
  end

  @doc """
  Returns the message for a value that is neither a keyword list nor a map, given as the text that
  shows it.
  """
  @spec invalid_value_message(String.t()) :: String.t()
  def invalid_value_message(value_text) do
    "the $data_transfer attribute takes a keyword list or a map, got #{value_text}"
  end

  @doc """
  Returns the message for a key the attribute doesn't take, given as the text that shows it.
  """
  @spec unknown_key_message(String.t()) :: String.t()
  def unknown_key_message(key_text) do
    "the $data_transfer attribute takes the :drop_effect key, got #{key_text}"
  end
end
