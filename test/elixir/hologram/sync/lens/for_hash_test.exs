defmodule Hologram.Sync.Lens.ForHashTest do
  # async: false - the lens keeps what it read in persistent terms, shared by the whole node.
  use Hologram.Test.DatabaseCase, async: false

  alias Hologram.Migrator
  alias Hologram.Sync.Lens

  setup do
    Lens.reset_cache()
    on_exit(&Lens.reset_cache/0)

    :ok
  end

  # The keys of the answers kept for good - an answer not kept is shared for a moment, as
  # `{:recent, until, outcome}`, with the processes that waited for it.
  defp kept_keys do
    for {key, value} <- :persistent_term.get(),
        is_tuple(key) and tuple_size(key) > 1 and elem(key, 0) == Lens,
        not match?({:recent, _until, _outcome}, value),
        do: key
  end

  # The suite's release holds no migration, so its files fold to an empty model, not the suite's:
  # what a dev node between a model edit and the migration generated for it looks like. A tab is
  # placed only along a history that leads to the running model, and nothing is kept, since
  # generating the migration changes the files without changing the model.
  test "serves nothing and keeps nothing while the release's files fold to another model" do
    Migrator.record_applied("20260101000000", DateTime.utc_now(), "h1")

    assert Lens.for_hash("h1") == :error
    assert Lens.for_hash("made-up") == :error
    assert kept_keys() == []
  end
end
