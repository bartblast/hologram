defmodule Hologram.Compiler.TracerTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.Tracer

  alias Hologram.Compiler.Tracer
  alias Hologram.Reflection

  # Names of modules that exist nowhere, so that no other compile in the VM records them.
  @module_1 Hologram.Test.Fixtures.Compiler.Tracer.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Tracer.Module2

  @test_dir Path.join([Reflection.tmp_dir(), "tests", "compiler", "tracer"])

  setup do
    tracers = Code.get_compiler_option(:tracers)
    on_exit(fn -> Code.put_compiler_option(:tracers, tracers) end)

    # Owned by the test process, so the table dies with each test.
    register()

    clean_dir(@test_dir)

    :ok
  end

  # take/1 compares bytes only, so a beam here is any binary.
  defp write_beam(module, bytecode) do
    beam_path = Path.join(@test_dir, "#{module}.beam")
    File.write!(beam_path, bytecode)
    String.to_charlist(beam_path)
  end

  defp report(module, bytecode) do
    trace({:on_module, bytecode, :none}, %Macro.Env{module: module})
  end

  describe "register/0" do
    test "creates the table" do
      assert :ets.whereis(Tracer) != :undefined
    end

    test "adds the tracer to the compiler's tracers once" do
      register()

      tracers = Code.get_compiler_option(:tracers)

      assert Enum.count(tracers, &(&1 == Tracer)) == 1
    end
  end

  describe "take/1" do
    test "returns a module whose beam holds its reported bytecode and forgets it" do
      beam_path = write_beam(@module_1, "new")
      report(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new([@module_1])
      assert take(%{@module_1 => beam_path}) == MapSet.new()
    end

    test "leaves a module whose beam does not hold its reported bytecode yet for the next take" do
      beam_path = write_beam(@module_1, "old")
      report(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new()

      write_beam(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new([@module_1])
    end

    test "leaves a module whose beam is not written yet for the next take" do
      beam_path =
        @test_dir
        |> Path.join("#{@module_1}.beam")
        |> String.to_charlist()

      report(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new()

      write_beam(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new([@module_1])
    end

    test "forgets a module that has no beam without returning it" do
      report(@module_1, "new")

      assert take(%{}) == MapSet.new()

      beam_path = write_beam(@module_1, "new")

      assert take(%{@module_1 => beam_path}) == MapSet.new()
    end

    test "takes each module on its own" do
      beam_path_1 = write_beam(@module_1, "new")
      beam_path_2 = write_beam(@module_2, "old")
      report(@module_1, "new")
      report(@module_2, "new")

      beam_paths = %{@module_1 => beam_path_1, @module_2 => beam_path_2}

      assert take(beam_paths) == MapSet.new([@module_1])

      write_beam(@module_2, "new")

      assert take(beam_paths) == MapSet.new([@module_2])
    end

    test "takes a module reported again by the latest bytecode" do
      beam_path = write_beam(@module_1, "second")
      report(@module_1, "first")
      report(@module_1, "second")

      assert take(%{@module_1 => beam_path}) == MapSet.new([@module_1])
    end

    test "returns the empty set when the table does not exist" do
      :ets.delete(Tracer)

      assert take(%{}) == MapSet.new()
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
      :ets.delete(Tracer)

      assert report(@module_1, "bytecode") == :ok
    end
  end
end
