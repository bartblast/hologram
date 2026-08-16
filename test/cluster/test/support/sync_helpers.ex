defmodule HologramClusterTests.SyncHelpers do
  @moduledoc """
  The peer-side half of the sync scenarios.

  It lives here rather than in the test module because a peer never loads one: ExUnit compiles
  test files in memory on the runner, while `test/support` is compiled into the app whose code
  paths every peer adds. An `rpc` into a test module answers `:undef`.
  """

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias HologramClusterTests.Entities.Item

  @doc """
  Creates an Item on the node this runs on and returns it.
  """
  @spec create_item(String.t(), String.t()) :: struct
  def create_item(slug, title) do
    Item
    |> Entity.new(slug: slug, title: title)
    |> create()
  end

  @doc """
  Creates an Item inside a transaction that is then HELD OPEN until released, and returns the
  process holding it.

  It sends `{:holding, pid}` to `notify` once the write has taken its transaction id, and commits
  when sent `:release`. A transaction takes its id at its first write and holds it to the end, so
  this is how a test makes a later transaction commit before an earlier one.
  """
  @spec hold_item_open(String.t(), String.t(), pid) :: pid
  def hold_item_open(slug, title, notify) do
    spawn(fn ->
      Connection.transaction(fn ->
        create_item(slug, title)

        send(notify, {:holding, self()})

        receive do
          :release -> :ok
        end
      end)
    end)
  end
end
