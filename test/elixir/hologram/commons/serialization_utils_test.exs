defmodule Hologram.Commons.SerializationUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.SerializationUtils

  describe "deserialize/1" do
    test "deserialize data" do
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

    test "when non-existing atoms are allowed" do
      # :non_existing_atom_fixture_1
      serialized_atom_fixture =
        <<131, 119, 27, 110, 111, 110, 95, 101, 120, 105, 115, 116, 105, 110, 103, 95, 97, 116,
          111, 109, 95, 102, 105, 120, 116, 117, 114, 101, 95, 49>>

      assert deserialize(serialized_atom_fixture, true)
    end

    test "when non-existing atoms are not allowed" do
      # :non_existing_atom_fixture_2
      serialized_atom_fixture =
        <<131, 119, 27, 110, 111, 110, 95, 101, 120, 105, 115, 116, 105, 110, 103, 95, 97, 116,
          111, 109, 95, 102, 105, 120, 116, 117, 114, 101, 95, 50>>

      assert_raise ArgumentError, fn ->
        deserialize(serialized_atom_fixture)
      end
    end
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

    assert :erlang.binary_to_term(result_1) == data_1
    assert :erlang.binary_to_term(result_2) == data_2
  end
end
