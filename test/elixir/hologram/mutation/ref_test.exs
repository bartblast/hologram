defmodule Hologram.Mutation.RefTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Mutation.Ref

  @ref %{client_id: "018f4c1e-0000-7000-8000-000000000001", seq: 7}

  describe "get/0" do
    test "answers nil when the calling process is applying no batch" do
      assert get() == nil
    end
  end

  describe "with_ref/2" do
    test "holds the batch for the function's extent" do
      assert with_ref(@ref, fn -> get() end) == @ref
    end

    test "returns the function's result" do
      assert with_ref(@ref, fn -> :done end) == :done
    end

    test "leaves no batch behind afterwards" do
      with_ref(@ref, fn -> :ok end)

      assert get() == nil
    end

    test "restores the enclosing batch afterwards" do
      inner_ref = %{client_id: "018f4c1e-0000-7000-8000-000000000002", seq: 1}

      held =
        with_ref(@ref, fn ->
          with_ref(inner_ref, fn -> get() end)

          get()
        end)

      assert held == @ref
    end

    test "restores the batch when the function raises" do
      assert_error RuntimeError, "boom", fn -> with_ref(@ref, fn -> raise "boom" end) end

      assert get() == nil
    end
  end
end
