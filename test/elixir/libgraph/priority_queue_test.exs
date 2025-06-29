defmodule PriorityQueue.Test do
  use ExUnit.Case, async: true
  doctest PriorityQueue

  test "inspect" do
    pq =
      Enum.reduce(0..4, PriorityQueue.new(), fn i, pq ->
        pq
        |> PriorityQueue.push(?a + i, i)
      end)

    str = "#{inspect(pq)}"
    assert "#PriorityQueue<size: 5, queue: 'abcde'>" = str
  end

  test "can enqueue random elements and pull them out in priority order" do
    pq =
      Enum.reduce(Enum.shuffle(0..9), PriorityQueue.new(), fn i, pq ->
        pq
        |> PriorityQueue.push(?a + i, i)
        |> PriorityQueue.push(?a + i, i)
      end)

    res =
      Enum.reduce(1..21, {pq, []}, fn _, {pq, acc} ->
        case PriorityQueue.pop(pq) do
          {:empty, _} ->
            Enum.reverse(acc)

          {{:value, char}, pq1} ->
            {pq1, [char | acc]}
        end
      end)

    assert [?a, ?a, ?b, ?b, ?c, ?c, ?d, ?d, ?e, ?e, ?f, ?f, ?g, ?g, ?h, ?h, ?i, ?i, ?j, ?j] = res
  end
end
