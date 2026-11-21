defmodule HologramSyncTests.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import HologramSyncTests.TestCase, only: [base_url: 0]

      alias Hologram.Test.SyncClient
    end
  end

  @doc """
  Returns the URL the test node serves the app at.
  """
  @spec base_url() :: String.t()
  def base_url, do: HologramSyncTestsWeb.Endpoint.url()
end
