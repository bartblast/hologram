defmodule HologramSyncTests.Consistency.ChecksTest do
  use ExUnit.Case, async: true

  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag

  @member "u-1"
  @space "s-1"

  # The member reads the space in the first state and loses it in the second, which commits at 16
  # with serial 101.
  setup do
    member_state = state(%{"name" => "space"}, [@member])
    left_state = state(%{"name" => "space"}, [])

    entries = [
      %{after_lock_at: 0, committed_at: 1, state: member_state, max_seq: 100, min_seq: 100},
      %{after_lock_at: 15, committed_at: 16, state: left_state, max_seq: 101, min_seq: 101}
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
    record = record(%{"name" => "space"}, cursor_seq: 101, opened_at: 10, received_at: 20)

    assert [%{candidates: [1]}] = Checks.leaks([record], entries, @member)
  end

  test "passes a row under a cursor below its user's loss", %{entries: entries} do
    record = record(%{"name" => "space"}, cursor_seq: 100, opened_at: 10, received_at: 20)

    assert Checks.leaks([record], entries, @member) == []
  end

  # A value no state had yet when the frame arrived: the rename got the commit lock after it.
  test "flags a value from a state that committed after the frame arrived" do
    entries = [
      %{
        after_lock_at: 0,
        committed_at: 1,
        state: state(%{"name" => "space"}, [@member]),
        max_seq: 100,
        min_seq: 100
      },
      %{
        after_lock_at: 15,
        committed_at: 16,
        state: state(%{"name" => "renamed"}, [@member]),
        max_seq: 101,
        min_seq: 101
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
        max_seq: 100,
        min_seq: 100
      },
      %{
        after_lock_at: 5,
        committed_at: 25,
        state: state(%{"name" => "space"}, []),
        max_seq: 101,
        min_seq: 101
      },
      %{
        after_lock_at: 6,
        committed_at: 7,
        state: state(%{"name" => "space"}, []),
        max_seq: 102,
        min_seq: 102
      }
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
             [%{record | named: [{SpaceMember, "member of #{@member}"}]}],
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
      %{after_lock_at: 0, committed_at: 1, state: before, max_seq: 100, min_seq: 100},
      %{after_lock_at: 15, committed_at: 16, state: after_rename, max_seq: 101, min_seq: 101}
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

    # Committed in lock order; the rename holds the lower serial, so a cursor past it floors at it.
    entries = [
      %{after_lock_at: 0, committed_at: 1, state: member_state, max_seq: 100, min_seq: 100},
      %{after_lock_at: 5, committed_at: 6, state: left_state, max_seq: 300, min_seq: 300},
      %{after_lock_at: 7, committed_at: 8, state: renamed_state, max_seq: 270, min_seq: 270}
    ]

    tag = %{
      record(%{"name" => "new"}, cursor_seq: 280, opened_at: 0, received_at: 20)
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

  # Check 3. Tag "t" is created holding serial 5 and tag "u" after it holding 9, and every user
  # reads both.
  describe "below_final/4" do
    setup do
      created = tags_state(%{"t" => {5, 5}})
      both = tags_state(%{"t" => {5, 5}, "u" => {9, 9}})

      entries = [
        %{after_lock_at: 0, committed_at: 1, max_seq: 5, min_seq: 5, state: created},
        %{after_lock_at: 10, committed_at: 11, max_seq: 9, min_seq: 9, state: both}
      ]

      %{entries: entries}
    end

    test "passes a view holding every row at or below its limit", %{entries: entries} do
      views = [view(5, 20, %{"t" => {5, 5}}), view(9, 30, %{"t" => {5, 5}, "u" => {9, 9}})]

      assert Checks.below_final(views, entries, @member, 9) == []
    end

    test "flags a row missing below the limit", %{entries: entries} do
      assert [%{id: "t", problem: :missing, wanted: {5, 5}}] =
               Checks.below_final([view(5, 20, %{})], entries, @member, 9)
    end

    test "flags a row showing a number other than its final one", %{entries: entries} do
      assert [%{id: "t", problem: :numbers, shown: {nil, nil}, wanted: {5, 5}}] =
               Checks.below_final([view(5, 20, %{"t" => {nil, nil}})], entries, @member, 9)
    end

    # The view's limit is below "u"'s number, so its numbers may still be held back.
    test "passes a row whose number is above the view's limit", %{entries: entries} do
      assert Checks.below_final([view(5, 30, %{"t" => {5, 5}})], entries, @member, 9) == []
    end

    test "flags a row showing a number above the view's limit", %{entries: entries} do
      view = %{
        view(5, 20, %{"t" => {5, 5}})
        | rows: %{Space => %{"s" => {5, 9}}, Tag => %{"t" => {5, 5}}}
      }

      assert [%{id: "s", problem: :above_final, shown: {5, 9}, type: Space}] =
               Checks.below_final([view], entries, @member, 9)
    end

    # A refill takes the limit an earlier fill's marker gave the type, but not the numbers it filed.
    test "passes a number an earlier fill's marker filed", %{entries: entries} do
      view = %{
        view(5, 20, %{"t" => {5, 5}})
        | proven: %{Space => 9},
          rows: %{Space => %{"s" => {5, 9}}, Tag => %{"t" => {5, 5}}}
      }

      assert Checks.below_final([view], entries, @member, 9) == []
    end

    test "judges only the types a view holds a limit for", %{entries: entries} do
      view = %{view(5, 20, %{}) | finals: %{Space => 5}, rows: %{}}

      assert Checks.below_final([view], entries, @member, 9) == []
    end

    # A fill's marker gives its type the fill's limit, and only that type.
    test "judges each type by its own limit", %{entries: entries} do
      view = %{
        view(9, 20, %{"t" => {5, 5}, "u" => {9, 9}})
        | finals: %{Space => 5, Tag => 9},
          rows: %{Space => %{"s" => {5, 9}}, Tag => %{"t" => {5, 5}, "u" => {9, 9}}}
      }

      assert [%{final_seq: 5, id: "s", problem: :above_final, type: Space}] =
               Checks.below_final([view], entries, @member, 9)
    end

    test "flags a number shown in a type with no limit", %{entries: entries} do
      view = %{
        view(5, 20, %{"t" => {5, 5}})
        | rows: %{Space => %{"s" => {5, 5}}, Tag => %{"t" => {5, 5}}}
      }

      assert [%{final_seq: nil, id: "s", problem: :above_final, type: Space}] =
               Checks.below_final([view], entries, @member, 9)
    end

    # The limit went out before the commit holding 9 locked, so the save was still running then.
    test "flags a commit below the limit that locked after the frame arrived", %{
      entries: entries
    } do
      assert [%{commit: 1, final_seq: 9, min_seq: 9, problem: :ended_after, type: Tag}] =
               Checks.below_final([view(9, 5, %{"t" => {5, 5}})], entries, @member, 9)
    end

    test "passes a commit below the limit that locked as the frame arrived", %{entries: entries} do
      view = view(9, 10, %{"t" => {5, 5}, "u" => {9, 9}})

      problems = Checks.below_final([view], entries, @member, 9)

      refute Enum.any?(problems, &(&1.problem == :ended_after))
    end

    # A commit that got the lock before the frame arrived can take a row away, so a row has to be
    # readable in every state from the floor on.
    test "passes a row a commit locked before the frame took away", %{entries: [created, both]} do
      gone = %{
        after_lock_at: 15,
        committed_at: 25,
        max_seq: 12,
        min_seq: 12,
        state: tags_state(%{})
      }

      entries = [created, both, gone]

      assert Checks.below_final([view(9, 20, %{})], entries, @member, 12) == []
    end

    # Saves take their serials before the commit lock, so a commit holding a serial at or below the
    # limit can lock after one holding a serial above it, and was sent all the same.
    test "judges a row a commit locked after one above the limit created", %{
      entries: [created | _]
    } do
      ahead = %{
        created
        | after_lock_at: 2,
          max_seq: 20,
          min_seq: 20,
          state: tags_state(%{"t" => {5, 5}, "v" => {20, 20}})
      }

      behind = %{
        created
        | after_lock_at: 3,
          max_seq: 7,
          min_seq: 7,
          state: tags_state(%{"t" => {5, 5}, "v" => {20, 20}, "w" => {7, 7}})
      }

      entries = [created, ahead, behind]
      view = view(10, 20, %{"t" => {5, 5}, "w" => {7, 7}})

      assert Checks.below_final([view], entries, @member, 20) == []

      assert [%{floor: 2, id: "w", problem: :missing, wanted: {7, 7}}] =
               Checks.below_final([view(10, 20, %{"t" => {5, 5}})], entries, @member, 20)
    end

    test "judges a row when the first commit holds a serial above the limit" do
      ahead = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 11,
        min_seq: 11,
        state: tags_state(%{"v" => {11, 11}})
      }

      behind = %{
        after_lock_at: 2,
        committed_at: 3,
        max_seq: 10,
        min_seq: 10,
        state: tags_state(%{"v" => {11, 11}, "w" => {10, 10}})
      }

      assert [%{floor: 1, id: "w", problem: :missing}] =
               Checks.below_final([view(10, 20, %{})], [ahead, behind], @member, 11)
    end

    # A row its user could read only from a later commit at or below the limit is judged from
    # there, not from the commit that created it.
    test "judges a row its user could read only once a later commit let them" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        state: numbered_space([])
      }

      joined = %{
        after_lock_at: 2,
        committed_at: 3,
        max_seq: 7,
        min_seq: 7,
        ops: ["add_member m-1 #{@space} #{@member}"],
        state: numbered_space([@member])
      }

      view = %{at: 20, finals: %{Space => 10}, rows: %{Space => %{}}}

      assert [%{floor: 1, id: @space, problem: :missing, type: Space}] =
               Checks.below_final([view], [created, joined], @member, 10)
    end

    # The server sends effects in serial order, so what a commit locked before the floor holding a
    # serial above the limit changed may not have come yet.
    test "passes a row a commit ahead of the floor above the limit let its user read" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_space #{@space} space"],
        state: numbered_space([])
      }

      joined = %{
        after_lock_at: 2,
        committed_at: 3,
        max_seq: 20,
        min_seq: 20,
        ops: ["add_member m #{@space} #{@member}"],
        state: numbered_space([@member])
      }

      floor = %{joined | after_lock_at: 4, committed_at: 5, max_seq: 7, min_seq: 7, ops: []}
      view = %{at: 20, finals: %{Space => 10}, rows: %{Space => %{}}}

      assert Checks.below_final([view], [created, joined, floor], @member, 20) == []
    end

    test "passes a row the floor's commit let its user read under a serial above the limit" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_space #{@space} space"],
        state: numbered_space([])
      }

      floor = %{
        after_lock_at: 2,
        committed_at: 3,
        max_seq: 20,
        min_seq: 7,
        ops: ["rename Tag t name name 2", "add_member m #{@space} #{@member}"],
        state: numbered_space([@member])
      }

      view = %{at: 20, finals: %{Space => 10}, rows: %{Space => %{}}}

      assert Checks.below_final([view], [created, floor], @member, 20) == []
    end

    # The server reads what a gained access lets through from the live tables, so a commit locked
    # after the floor holding a serial above the limit can keep a row from coming until its effect
    # does - here a member joining the space the card's board is in.
    test "passes a row a commit after the floor above the limit names the access of" do
      assert Checks.below_final([card_view(20)], card_entries(2), @member, 20) == []
    end

    test "judges a row a commit above the limit locked after the frame names the access of" do
      assert [%{id: "c-1", problem: :missing, type: Card}] =
               Checks.below_final([card_view(20)], card_entries(20), @member, 20)
    end

    # A type-wide grant names no board, so it is matched by its user. Locked ahead of the floor
    # under a serial above the limit, it may still be on its way.
    test "passes a row a type-wide grant ahead of the floor above the limit lets its user read" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_board b-1 #{@space} board false"],
        state: card_state([])
      }

      grants = MapSet.new([{@member, :all}])

      granted = %{
        after_lock_at: 2,
        committed_at: 4,
        max_seq: 20,
        min_seq: 20,
        ops: ["grant_wide #{@member}"],
        state: %{card_state([]) | grants: grants}
      }

      floor = %{
        after_lock_at: 3,
        committed_at: 5,
        max_seq: 7,
        min_seq: 7,
        ops: ["create_tag t-1 t-1"],
        state: %{card_state([]) | grants: grants}
      }

      view = %{at: 20, finals: %{Board => 10}, rows: %{Board => %{}}}

      assert Checks.below_final([view], [created, granted, floor], @member, 20) == []
    end

    test "judges a row a commit above the limit names only its user beside" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_space #{@space} space"],
        state: numbered_space([@member])
      }

      elsewhere = %{
        created
        | after_lock_at: 2,
          committed_at: 3,
          max_seq: 20,
          min_seq: 20,
          ops: ["add_member m-2 s-2 #{@member}"]
      }

      view = %{at: 20, finals: %{Space => 10}, rows: %{Space => %{}}}

      assert [%{id: @space, problem: :missing}] =
               Checks.below_final([view], [created, elsewhere], @member, 20)
    end

    test "judges a row a commit within the limit locked after the frame takes away" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_tag t-1 t-1"],
        state: tags_state(%{"t-1" => {5, 5}})
      }

      deleted = %{
        created
        | after_lock_at: 30,
          committed_at: 31,
          max_seq: 8,
          min_seq: 8,
          ops: ["delete_tag t-1"],
          state: tags_state(%{})
      }

      assert [
               %{commit: 1, min_seq: 8, problem: :ended_after},
               %{id: "t-1", problem: :missing}
             ] = Checks.below_final([view(10, 20, %{})], [created, deleted], @member, 20)
    end

    # The card is on b-1 when the frame arrives, so a commit above the limit naming b-2 can't keep
    # it away, whatever moves it to b-2 after.
    test "judges a row by what its access goes through when the frame arrives" do
      state = card_state([@member])

      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_card c-1 b-1"],
        state: state
      }

      elsewhere = %{created | after_lock_at: 2, max_seq: 11, min_seq: 11, ops: ["archive b-2"]}

      moved = %{
        created
        | after_lock_at: 30,
          committed_at: 31,
          max_seq: 12,
          min_seq: 12,
          ops: ["move_card c-1 b-2"],
          state: put_in(state, [:rows, Card, "c-1", "board_id"], "b-2")
      }

      assert [%{id: "c-1", problem: :missing}] =
               Checks.below_final([card_view(20)], [created, elsewhere, moved], @member, 20)
    end

    test "judges a row a type-wide grant on its way can't let its user read" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_tag t-1 t-1"],
        state: tags_state(%{"t-1" => {5, 5}})
      }

      granted = %{
        created
        | after_lock_at: 2,
          max_seq: 20,
          min_seq: 20,
          ops: ["grant_wide #{@member}"]
      }

      assert [%{id: "t-1", problem: :missing}] =
               Checks.below_final([view(10, 20, %{})], [created, granted], @member, 20)
    end

    test "judges a row for a client with no user when a type-wide grant is on its way" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        ops: ["create_tag t-1 t-1"],
        state: tags_state(%{"t-1" => {5, 5}})
      }

      granted = %{created | after_lock_at: 2, max_seq: 20, min_seq: 20, ops: ["grant_wide u-2"]}

      assert [%{id: "t-1", problem: :missing}] =
               Checks.below_final([view(10, 20, %{})], [created, granted], nil, 20)
    end

    # The updated number is judged from the floor, so a commit locked before it holding a serial
    # above the limit, and changing something else, leaves it judged.
    test "judges a row's updated number from the floor" do
      created = %{
        after_lock_at: 0,
        committed_at: 1,
        max_seq: 5,
        min_seq: 5,
        state: tags_state(%{"t-1" => {5, 5}})
      }

      ahead =
        Map.merge(created, %{
          after_lock_at: 2,
          max_seq: 20,
          min_seq: 20,
          ops: ["create_tag v-1 v-1"],
          state: tags_state(%{"t-1" => {5, 5}, "v-1" => {20, 20}})
        })

      updated = %{
        created
        | after_lock_at: 4,
          max_seq: 7,
          min_seq: 7,
          state: tags_state(%{"t-1" => {5, 7}, "v-1" => {20, 20}})
      }

      assert [%{id: "t-1", problem: :numbers, shown: {5, nil}, wanted: {5, 7}}] =
               Checks.below_final(
                 [view(10, 20, %{"t-1" => {5, nil}})],
                 [created, ahead, updated],
                 @member,
                 20
               )
    end

    test "flags a limit short of the last commit's serials once the writes stopped", %{
      entries: entries
    } do
      assert [%{final_seq: 5, last_seq: 9, problem: :not_final}] =
               Checks.below_final([], entries, @member, 5)

      assert [%{final_seq: nil, problem: :not_final}] =
               Checks.below_final([], entries, @member, nil)
    end
  end

  defp tags_state(numbered) do
    rows = Map.new(Model.types(), &{&1, %{}})

    %{
      grants: MapSet.new(),
      pairs: MapSet.new(),
      rows: %{rows | Tag => Map.new(numbered, fn {id, _seqs} -> {id, %{"name" => id}} end)},
      seqs: %{Tag => numbered}
    }
  end

  defp view(final_seq, at, rows) do
    %{at: at, finals: %{Tag => final_seq}, proven: %{}, rows: %{Tag => rows}}
  end

  defp record(carried, opts) do
    %{
      applied?: true,
      carried: carried,
      cursor_seq: Keyword.get(opts, :cursor_seq),
      id: @space,
      named: [],
      opened_at: Keyword.fetch!(opts, :opened_at),
      received_at: Keyword.fetch!(opts, :received_at),
      type: Space
    }
  end

  # A card created at 5 on a board in the space, whose user is a member, then a commit holding 20,
  # locked at the given time, that has another user join the space.
  defp card_entries(joined_at) do
    created = %{
      after_lock_at: 0,
      committed_at: 1,
      max_seq: 5,
      min_seq: 5,
      ops: ["create_card c-1 b-1 card"],
      state: card_state([@member])
    }

    joined = %{
      after_lock_at: joined_at,
      committed_at: joined_at + 1,
      max_seq: 20,
      min_seq: 20,
      ops: ["add_member m-2 #{@space} u-2"],
      state: card_state([@member, "u-2"])
    }

    [created, joined]
  end

  defp card_view(at), do: %{at: at, finals: %{Card => 10}, rows: %{Card => %{}}}

  defp card_state(members) do
    members
    |> numbered_space()
    |> put_in([:rows, Board], %{"b-1" => %{"archived" => false, "space_id" => @space}})
    |> put_in([:rows, Card], %{"c-1" => %{"board_id" => "b-1"}})
    |> Map.put(:seqs, %{Board => %{"b-1" => {5, 5}}, Card => %{"c-1" => {5, 5}}})
  end

  defp numbered_space(members) do
    %{"name" => "space"}
    |> state(members)
    |> Map.put(:seqs, %{Space => %{@space => {5, 5}}})
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
