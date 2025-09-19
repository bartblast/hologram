defmodule Hologram.Commons.KeywordUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.KeywordUtils

  describe "deep_merge/2" do
    test "both keyword lists are empty" do
      result = deep_merge([], [])
      assert result == []
    end

    test "first keyword list is empty" do
      result = deep_merge([], a: 1, b: 2)
      assert result == [a: 1, b: 2]
    end

    test "second keyword list is empty" do
      result = deep_merge([a: 1, b: 2], [])
      assert result == [a: 1, b: 2]
    end

    test "flat keyword lists with no overlapping keys" do
      result = deep_merge([a: 1, b: 2], c: 3, d: 4)
      assert result == [a: 1, b: 2, c: 3, d: 4]
    end

    test "flat keyword lists with overlapping keys, second takes precedence" do
      result = deep_merge([a: 1, b: 2], b: 3, c: 4)
      assert result == [a: 1, b: 3, c: 4]
    end

    test "merge with all overlapping keys" do
      result = deep_merge([a: 1, b: 2], a: 10, b: 20)
      assert result == [a: 10, b: 20]
    end

    test "nested keyword lists are merged recursively" do
      keyword_1 = [a: 1, b: [c: 2, d: 3]]
      keyword_2 = [b: [e: 4, f: 5], g: 6]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [a: 1, b: [c: 2, d: 3, e: 4, f: 5], g: 6]
    end

    test "nested keyword lists with overlapping keys, second takes precedence" do
      keyword_1 = [a: 1, b: [c: 2, d: 3]]
      keyword_2 = [b: [c: 20, e: 4], f: 5]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [a: 1, b: [d: 3, c: 20, e: 4], f: 5]
    end

    test "deeply nested keyword lists" do
      keyword_1 = [a: [b: [c: [d: 1, e: 2]]]]
      keyword_2 = [a: [b: [c: [f: 3], g: 4]], h: 5]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [a: [b: [c: [d: 1, e: 2, f: 3], g: 4]], h: 5]
    end

    test "keyword list replaced by non-keyword value" do
      keyword_1 = [config: [database: "postgres", port: 5432]]
      keyword_2 = [config: nil]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [config: nil]
    end

    test "non-keyword value replaced by keyword list" do
      keyword_1 = [config: "simple_string"]
      keyword_2 = [config: [database: "postgres", port: 5432]]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [config: [database: "postgres", port: 5432]]
    end

    test "preserves order from first keyword list, appends new keys from second" do
      keyword_1 = [z: 1, y: 2, x: 3]
      keyword_2 = [y: 20, w: 4, v: 5]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [z: 1, x: 3, y: 20, w: 4, v: 5]
    end

    test "handles nil values correctly" do
      keyword_1 = [a: nil, b: [c: nil, d: 1]]
      keyword_2 = [a: 1, b: [c: 2, e: nil]]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [a: 1, b: [d: 1, c: 2, e: nil]]
    end

    test "handles boolean values correctly" do
      keyword_1 = [enabled: true, features: [beta: false, stable: true]]
      keyword_2 = [enabled: false, features: [beta: true, experimental: true]]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [enabled: false, features: [stable: true, beta: true, experimental: true]]
    end

    test "handles numeric values of different types" do
      keyword_1 = [count: 42, rate: 1.5]
      keyword_2 = [count: 42.0, precision: 0.001]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [rate: 1.5, count: 42.0, precision: 0.001]
    end

    test "handles lists that are not keyword lists" do
      keyword_1 = [items: [1, 2, 3], config: [enabled: true]]
      keyword_2 = [items: [:a, :b], config: [timeout: 1000]]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [items: [:a, :b], config: [enabled: true, timeout: 1000]]
    end

    test "handles empty nested keyword lists" do
      keyword_1 = [a: [], b: [c: 1]]
      keyword_2 = [a: [d: 2], b: []]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [a: [d: 2], b: [c: 1]]
    end

    test "handles duplicate keys in keyword lists" do
      keyword_1 = [a: 1, a: 2, b: 3]
      keyword_2 = [a: 10, c: 4]
      result = deep_merge(keyword_1, keyword_2)

      assert result == [b: 3, a: 10, c: 4]
    end

    test "complex real-world configuration merge scenario" do
      default_config = [
        database: [
          adapter: :postgres,
          pool_size: 10,
          timeout: 5_000,
          ssl: [verify: :verify_peer]
        ],
        web: [
          port: 4000,
          host: "localhost"
        ],
        logging: [
          level: :info,
          backends: [:console]
        ]
      ]

      user_config = [
        database: [
          pool_size: 20,
          ssl: [verify: :verify_none, keyfile: "/path/to/key"]
        ],
        web: [
          port: 8080
        ],
        cache: [
          adapter: :redis,
          host: "redis.example.com"
        ]
      ]

      result = deep_merge(default_config, user_config)

      expected = [
        logging: [
          level: :info,
          backends: [:console]
        ],
        database: [
          adapter: :postgres,
          timeout: 5_000,
          pool_size: 20,
          ssl: [verify: :verify_none, keyfile: "/path/to/key"]
        ],
        web: [host: "localhost", port: 8080],
        cache: [adapter: :redis, host: "redis.example.com"]
      ]

      assert result == expected
    end
  end
end
