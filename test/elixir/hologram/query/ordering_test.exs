defmodule Hologram.Query.OrderingTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Ordering

  describe "compare/3" do
    test "compares an integer and a float as two floats" do
      assert compare(9_007_199_254_740_993, 9_007_199_254_740_992.0) == :eq
      assert compare(9_007_199_254_740_992.0, 9_007_199_254_740_993) == :eq
    end

    test "compares two integers exactly" do
      assert compare(9_007_199_254_740_993, 9_007_199_254_740_992) == :gt
    end

    test "compares an integer no column can hold with a float without raising" do
      assert compare(10 ** 400, 1.0) == :gt
      assert compare(1.0, 10 ** 400) == :lt
    end
  end

  describe "widened/2" do
    test "reads an integer as a float for a float field" do
      assert widened(9_007_199_254_740_993, :float) === 9_007_199_254_740_992.0
    end

    test "leaves an integer as it is for any other field" do
      assert widened(9_007_199_254_740_993, :integer) === 9_007_199_254_740_993
    end

    test "reads an integer no column can hold as a float for a float field" do
      assert widened(18_446_744_073_709_551_617, :float) === 18_446_744_073_709_551_616.0
    end

    test "reads the integer just past the largest float's digits as that float" do
      integer = trunc(1.7_976_931_348_623_157e308) + 1

      assert widened(integer, :float) === 1.7_976_931_348_623_157e308
    end

    test "leaves an integer no float can hold as it is" do
      assert widened(10 ** 400, :float) === 10 ** 400
    end

    test "leaves nil as it is" do
      assert widened(nil, :float) == nil
    end
  end
end
