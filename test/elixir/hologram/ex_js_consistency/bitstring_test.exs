defmodule Hologram.ExJsConsistency.BitstringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related Javascript test in test/javascript/type_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils, only: [to_bit_list: 1]

  describe "integer" do
    test "defaults for positive value that fits in 8 bits" do
      # 170 == 0b10101010
      assert to_bit_list(<<170>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for negative value that fits in 8 bits" do
      # -22 == 0b11101010
      # 234 == 0b11101010
      assert to_bit_list(<<-22>>) == to_bit_list(<<234>>)
      assert to_bit_list(<<-22>>) == [1, 1, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for positive value that fits in 12 bits" do
      # 4010 == 0b111110101010
      # 170 == 0b10101010
      assert to_bit_list(<<4010>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for negative value that fits in 12 bits" do
      # -86 == 0b111110101010
      # 170 == 0b10101010
      assert to_bit_list(<<-86>>) == to_bit_list(<<170>>)
      assert to_bit_list(<<-86>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end
  end
end
