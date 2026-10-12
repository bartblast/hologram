defmodule Hologram.Compiler.TracerTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Tracer

  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.Tracer
  alias Hologram.Reflection

  # Names of modules that exist nowhere, so that no other compile in the VM records them.
  @module_1 Hologram.Test.Fixtures.Compiler.Tracer.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Tracer.Module2

  @test_dir Path.join([Reflection.tmp_dir(), "tests", "compiler", "tracer"])

  setup do
    tracers = Code.get_compiler_option(:tracers)
    on_exit(fn -> Code.put_compiler_option(:tracers, tracers) end)

    # A fresh cache registers the tracer with a fresh table, so no test sees another's records.
    stop_cache()
    Cache.get()
    on_exit(&stop_cache/0)

    clean_dir(@test_dir)

    :ok
  end

  defp report(module, bytecode) do
    trace({:on_module, bytecode, :none}, %Macro.Env{module: module})
  end

  defp stop_cache do
    if Process.whereis(Cache), do: GenServer.stop(Cache)
  end

  # peek/1 compares bytes only, so a beam here is any binary.
  defp write_beam(module, bytecode) do
    beam_path = Path.join(@test_dir, "#{module}.beam")
    File.write!(beam_path, bytecode)
    String.to_charlist(beam_path)
  end

  describe "forget/1" do
    test "forgets the given records" do
      beam_path = write_beam(@module_1, "new")
      report(@module_1, "new")

      {_modules, records} = peek(%{@module_1 => beam_path})

      assert forget(records) == :ok
      assert peek(%{@module_1 => beam_path}) == {MapSet.new(), []}
    end

    test "keeps the record of a module compiled again since" do
      beam_path = write_beam(@module_1, "first")
      report(@module_1, "first")

      {_modules, records} = peek(%{@module_1 => beam_path})

      report(@module_1, "second")
      forget(records)

      assert :ets.lookup(Tracer, @module_1) == [{@module_1, "second"}]
    end

    test "returns ok when the table does not exist" do
      GenServer.stop(Cache)

      assert forget([{@module_1, "new"}]) == :ok
    end
  end

  describe "peek/1" do
    test "returns a module whose beam holds its reported bytecode, with its record" do
      beam_path = write_beam(@module_1, "new")
      report(@module_1, "new")

      expected = {MapSet.new([@module_1]), [{@module_1, "new"}]}

      assert peek(%{@module_1 => beam_path}) == expected
      assert peek(%{@module_1 => beam_path}) == expected
    end

    test "leaves a module whose beam does not hold its reported bytecode yet for the next call" do
      beam_path = write_beam(@module_1, "old")
      report(@module_1, "new")

      assert peek(%{@module_1 => beam_path}) == {MapSet.new(), []}

      write_beam(@module_1, "new")

      assert peek(%{@module_1 => beam_path}) == {MapSet.new([@module_1]), [{@module_1, "new"}]}
    end

    test "leaves a module whose beam is not written yet for the next call" do
      beam_path =
        @test_dir
        |> Path.join("#{@module_1}.beam")
        |> String.to_charlist()

      report(@module_1, "new")

      assert peek(%{@module_1 => beam_path}) == {MapSet.new(), []}

      write_beam(@module_1, "new")

      assert peek(%{@module_1 => beam_path}) == {MapSet.new([@module_1]), [{@module_1, "new"}]}
    end

    test "returns the record of a module that has no beam, and not the module" do
      report(@module_1, "new")

      assert peek(%{}) == {MapSet.new(), [{@module_1, "new"}]}
    end

    test "reads each module on its own" do
      beam_path_1 = write_beam(@module_1, "new")
      beam_path_2 = write_beam(@module_2, "old")
      report(@module_1, "new")
      report(@module_2, "new")

      beam_paths = %{@module_1 => beam_path_1, @module_2 => beam_path_2}

      assert peek(beam_paths) == {MapSet.new([@module_1]), [{@module_1, "new"}]}

      write_beam(@module_2, "new")

      {modules, records} = peek(beam_paths)

      assert modules == MapSet.new([@module_1, @module_2])
      assert Enum.sort(records) == [{@module_1, "new"}, {@module_2, "new"}]
    end

    test "reads a module reported again by the latest bytecode" do
      beam_path = write_beam(@module_1, "second")
      report(@module_1, "first")
      report(@module_1, "second")

      assert peek(%{@module_1 => beam_path}) ==
               {MapSet.new([@module_1]), [{@module_1, "second"}]}
    end

    test "returns the empty set and no record when the table does not exist" do
      GenServer.stop(Cache)

      assert peek(%{}) == {MapSet.new(), []}
    end
  end

  describe "register/0" do
    test "creates the table" do
      GenServer.stop(Cache)
      assert :ets.whereis(Tracer) == :undefined

      register()

      assert :ets.whereis(Tracer) != :undefined
    end

    test "adds the tracer to the compiler's tracers once" do
      register()

      tracers = Code.get_compiler_option(:tracers)

      assert Enum.count(tracers, &(&1 == Tracer)) == 1
    end
  end

  describe "trace/2" do
    test "records the bytecode of the module of an on_module event" do
      assert report(@module_1, "bytecode") == :ok
      assert :ets.lookup(Tracer, @module_1) == [{@module_1, "bytecode"}]
    end

    test "keeps only the latest bytecode of a module" do
      report(@module_1, "first")
      report(@module_1, "second")

      assert :ets.lookup(Tracer, @module_1) == [{@module_1, "second"}]
    end

    test "ignores the other events" do
      env = %Macro.Env{module: @module_1}

      assert trace({:remote_function, [], Enum, :map, 2}, env) == :ok
      assert :ets.tab2list(Tracer) == []
    end

    test "returns ok when the table does not exist" do
      GenServer.stop(Cache)

      assert report(@module_1, "bytecode") == :ok
    end
  end
end
