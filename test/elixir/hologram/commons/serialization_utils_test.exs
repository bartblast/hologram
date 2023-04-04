defmodule Hologram.Commons.SerializationUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.SerializationUtils

  test "deserialize/1" do
    data = %{
      key_2: 2,
      key_1: {1, 3},
      key_3: %{
        b: 22,
        a: 11
      }
    }

    serialized = :erlang.term_to_binary(data, compressed: 9)

    assert deserialize(serialized) == data
  end

  test "serialize/1" do
    data_1 = %{
      key_2: 2,
      key_1: {1, 3},
      key_3: %{
        b: 22,
        a: 11
      }
    }

    data_2 = %{
      key_3: %{
        a: 11,
        b: 22
      },
      key_1: {1, 3},
      key_2: 2
    }

    result_1 = serialize(data_1)
    result_2 = serialize(data_2)

    assert result_1 == result_2
    assert byte_size(result_1) == 53

    assert :erlang.binary_to_term(result_1) == data_1
    assert :erlang.binary_to_term(result_2) == data_2
  end
end
