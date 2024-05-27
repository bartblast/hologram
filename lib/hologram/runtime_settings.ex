defmodule Hologram.RuntimeSettings do
  @prefetch_page_action_name :__prefetch_page__

  @doc """
  Returns the action name used for page prefetching.
  """
  @spec prefetch_page_action_name() :: atom
  def prefetch_page_action_name do
    @prefetch_page_action_name
  end
end
