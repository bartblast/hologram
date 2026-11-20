defmodule HologramSyncTests.Consistency.ChecksTest do
  use ExUnit.Case, async: true

  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag

  @member "member"
  @space "space"

  # The member reads the space in the first state and loses it in the second, which commits at 16
  # with transaction id 101.
  setup do
    member_state = state(%{"name" => "space"}, [@member])
    left_state = state(%{"name" => "space"}, [])

    entries = [
      %{after_lock_at: 0, committed_at: 1, state: member_state, xid: 100},
      %{after_lock_at: 15, committed_at: 16, state: left_state, xid: 101}
    ]

    %{entries: entries}
  end

  test "flags a row its user could read in no state the frame could come from", %{
    entries: entries
  } do
    record = record(%{"name" => "never this name"}, opened_at: 10, received_at: 20)

    assert [%{candidates: [0, 1], record: ^record}] = Checks.leaks([record], entries, @member)
  end

  test "passes a row its user lost after the connection opened and before the frame arrived", %{
    entries: entries
  } do
    record = record(%{"name" => "space"}, opened_at: 10, received_at: 20)

    assert Checks.leaks([record], entries, @member) == []
  end

  test "flags a row with unchanged values on a connection opened after its user lost it", %{
    entries: entries
  } do
    record = record(%{"name" => "space"}, opened_at: 20, received_at: 30)

    assert [%{candidates: [1]}] = Checks.leaks([record], entries, @member)
  end

  test "flags a row under a cursor past its user's loss", %{entries: entries} do
    record = record(%{"name" => "space"}, cursor_tx: 102, opened_at: 10, received_at: 20)

    assert [%{candidates: [1]}] = Checks.leaks([record], entries, @member)
  end

  test "passes a row under a cursor below its user's loss", %{entries: entries} do
    record = record(%{"name" => "space"}, cursor_tx: 101, opened_at: 10, received_at: 20)

    assert Checks.leaks([record], entries, @member) == []
  end

  # A value no state had yet when the frame arrived: the rename got the commit lock after it.
  test "flags a value from a state that committed after the frame arrived" do
    entries = [
      %{
        after_lock_at: 0,
        committed_at: 1,
        state: state(%{"name" => "space"}, [@member]),
        xid: 100
      },
      %{
        after_lock_at: 15,
        committed_at: 16,
        state: state(%{"name" => "renamed"}, [@member]),
        xid: 101
      }
    ]

    record = record(%{"name" => "renamed"}, opened_at: 10, received_at: 14)

    assert [%{candidates: [0]}] = Checks.leaks([record], entries, @member)
    assert Checks.leaks([%{record | received_at: 20}], entries, @member) == []
  end

  # Writers read their commit times apart, so a later state's can come out earlier: here the third
  # committed before the connection opened, so neither earlier state was current then, though the
  # second read its commit time after the open.
  test "takes a state as gone once any later state committed before the connection opened" do
    entries = [
      %{
        after_lock_at: 0,
        committed_at: 1,
        state: state(%{"name" => "space"}, [@member]),
        xid: 100
      },
      %{after_lock_at: 5, committed_at: 25, state: state(%{"name" => "space"}, []), xid: 101},
      %{after_lock_at: 6, committed_at: 7, state: state(%{"name" => "space"}, []), xid: 102}
    ]

    record = record(%{"name" => "space"}, opened_at: 10, received_at: 30)

    assert [%{candidates: [2]}] = Checks.leaks([record], entries, @member)
  end

  # A set names its rows' ids, so naming one the user can't read tells them it exists.
  test "flags a row whose sets name a row its user couldn't read", %{entries: entries} do
    record = %{
      record(%{"name" => "space"}, opened_at: 10, received_at: 20)
      | named: [{SpaceMember, "member of someone else"}]
    }

    assert [%{record: ^record}] = Checks.leaks([record], entries, @member)

    assert Checks.leaks(
             [%{record | named: [{SpaceMember, "member of member"}]}],
             entries,
             @member
           ) == []
  end

  # A row handed over whole carries sets built from what the client holds, read a moment apart from
  # its values, so a named row only has to be readable in some state the frame could come from.
  test "passes a named row its user could read in another state the frame could come from" do
    member_row = %{"m" => %{"space_id" => @space, "user_id" => @member}}

    with_old_tag =
      put_in(state(%{"name" => "space"}, [])[:rows][Tag], %{"t" => %{"name" => "old"}})

    before = put_in(with_old_tag[:rows][SpaceMember], member_row)

    after_rename =
      put_in(state(%{"name" => "space"}, [])[:rows][Tag], %{"t" => %{"name" => "new"}})

    entries = [
      %{after_lock_at: 0, committed_at: 1, state: before, xid: 100},
      %{after_lock_at: 15, committed_at: 16, state: after_rename, xid: 101}
    ]

    record = %{
      record(%{"name" => "new"}, opened_at: 10, received_at: 20)
      | id: "t",
        named: [{SpaceMember, "m"}],
        type: Tag
    }

    assert Checks.leaks([record], entries, @member) == []
  end

  # A named row, or the row a pair is filed under, is one the session holds - readable when it read
  # or told it, which can be below the frame's place, though never before the connection opened.
  test "judges a named row and a pair's row since the open, below the frame's place" do
    member_row = %{"m" => %{"space_id" => @space, "user_id" => @member}}
    tags = fn name -> %{"t" => %{"name" => name}} end

    with_member = put_in(state(%{"name" => "space"}, [])[:rows][SpaceMember], member_row)
    member_state = put_in(with_member[:rows][Tag], tags.("old"))
    left_state = put_in(state(%{"name" => "space"}, [])[:rows][Tag], tags.("old"))
    renamed_state = put_in(state(%{"name" => "space"}, [])[:rows][Tag], tags.("new"))

    # Committed in lock order; the rename has the lower id, so a cursor past it floors at it.
    entries = [
      %{after_lock_at: 0, committed_at: 1, state: member_state, xid: 100},
      %{after_lock_at: 5, committed_at: 6, state: left_state, xid: 300},
      %{after_lock_at: 7, committed_at: 8, state: renamed_state, xid: 270}
    ]

    tag = %{
      record(%{"name" => "new"}, cursor_tx: 280, opened_at: 0, received_at: 20)
      | id: "t",
        named: [{SpaceMember, "m"}],
        type: Tag
    }

    pair =
      tag
      |> Map.merge(%{carried: %{}, id: "m", named: [{Tag, "t"}], type: SpaceMember})
      |> Map.put(:pair?, true)

    assert Checks.leaks([tag, pair], entries, @member) == []
    assert [_tag_leak, _pair_leak] = Checks.leaks([tag, pair], entries, "someone else")
  end

  defp record(carried, opts) do
    %{
      applied?: true,
      carried: carried,
      cursor_tx: Keyword.get(opts, :cursor_tx),
      id: @space,
      named: [],
      opened_at: Keyword.fetch!(opts, :opened_at),
      received_at: Keyword.fetch!(opts, :received_at),
      type: Space
    }
  end

  defp state(space, member_ids) do
    rows = Map.new(Model.types(), &{&1, %{}})

    members =
      Map.new(member_ids, &{"member of #{&1}", %{"space_id" => @space, "user_id" => &1}})

    %{
      grants: MapSet.new(),
      pairs: MapSet.new(),
      rows: %{rows | Space => %{@space => space}, SpaceMember => members}
    }
  end
end
