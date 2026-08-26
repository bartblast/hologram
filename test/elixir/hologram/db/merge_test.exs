defmodule Hologram.DB.MergeTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Merge

  describe "resolve/4" do
    # The stamp is below the stored revision on purpose: seeing what the row still holds is enough
    # on its own, and a write that only ever won by being newer could not be told from this one.
    test "sets a column the writer saw unchanged" do
      assert resolve(%{a: true}, %{a: 5}, 3, %{a: 5}) == {%{a: true}, []}
    end

    test "sets a column the write is newer than" do
      assert resolve(%{a: true}, %{a: 5}, 10, %{a: 9}) == {%{a: true}, []}
    end

    test "drops a column the row holds a newer revision of" do
      assert resolve(%{a: true}, %{a: 5}, 7, %{a: 9}) == {%{}, [:a]}
    end

    test "drops a column whose stored revision equals the stamp" do
      assert resolve(%{a: true}, %{a: 5}, 9, %{a: 9}) == {%{}, [:a]}
    end

    test "reads a column the row holds no revision of as never set" do
      assert resolve(%{a: true}, %{}, 1, %{}) == {%{a: true}, []}
    end

    test "reads a column the write names no revision of as never seen" do
      assert resolve(%{a: true}, %{}, 7, %{a: 9}) == {%{}, [:a]}
      assert resolve(%{a: true}, %{}, 10, %{a: 9}) == {%{a: true}, []}
    end

    test "leaves a column the write does not name alone" do
      assert resolve(%{a: true}, %{a: 5}, 7, %{a: 5, b: 9}) == {%{a: true}, []}
    end

    test "resolves each column the write names on its own" do
      assert resolve(%{a: true, b: "x"}, %{a: 5, b: 5}, 7, %{a: 5, b: 9}) == {%{a: true}, [:b]}
    end

    test "lists the lost columns sorted" do
      assert resolve(%{c: 1, a: 2, b: 3}, %{}, 7, %{a: 9, b: 9, c: 9}) == {%{}, [:a, :b, :c]}
    end

    test "resolves a write naming no columns as nothing won and nothing lost" do
      assert resolve(%{}, %{}, 7, %{a: 9}) == {%{}, []}
    end
  end

  describe "resolve_delete/3" do
    test "deletes when the writer saw every column unchanged" do
      assert resolve_delete(%{a: 5, b: 9}, 3, %{a: 5, b: 9}) == :delete
    end

    test "deletes when the write is newer than every column that moved" do
      assert resolve_delete(%{a: 5, b: 5}, 10, %{a: 5, b: 9}) == :delete
    end

    test "drops the delete when any column moved past the write" do
      assert resolve_delete(%{a: 5, b: 5}, 7, %{a: 5, b: 9}) == :drop
    end

    test "deletes a row holding no revisions" do
      assert resolve_delete(%{}, 7, %{}) == :delete
    end

    test "ignores a revision the write names that the row does not hold" do
      assert resolve_delete(%{a: 5, gone: 9}, 7, %{a: 5}) == :delete
    end
  end
end
