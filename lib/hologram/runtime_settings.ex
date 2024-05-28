defmodule Hologram.RuntimeSettings do
  @navigate_to_prefetched_page_action_name :__navigate_to_prefetched_page__
  @prefetch_page_action_name :__prefetch_page__

  @doc """
  Returns the action name used for navigating to a prefetched page.
  """
  @spec navigate_to_prefetched_page_action_name() :: atom
  def navigate_to_prefetched_page_action_name do
    @navigate_to_prefetched_page_action_name
  end

  @doc """
  Returns the action name used for page prefetching.
  """
  @spec prefetch_page_action_name() :: atom
  def prefetch_page_action_name do
    @prefetch_page_action_name
  end
end
