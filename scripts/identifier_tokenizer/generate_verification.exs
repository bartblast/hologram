#!/usr/bin/env elixir

# Script to generate verification data for the manual String.Tokenizer port: inputs paired with
# the BEAM's full tokenize/1 results, consumed by verify_tokenizer.mjs. The corpus layers:
#
#   * every usable single codepoint (the unusable ones all yield {:error, :empty}, which the
#     verifier checks against the constant without needing them dumped)
#   * an underscore followed by each usable codepoint, exercising continuation
#   * an underscore followed by a deterministic sample of unusable codepoints, exercising the
#     stop and unexpected-token paths
#   * cross-script pairs - two representatives of every script signature in
#     scriptsets_elixir.txt combined pairwise, plain and underscore-separated, exercising
#     mixed-script detection and chunking
#   * every module and exported function name of a spread of loaded applications - the shapes
#     the runtime actually renders
#
# Line format: input codepoints comma-joined, "|", then the result -
#   ok:<kind>:<acc>:<rest>:<length>:<ascii>:<special>   (lists comma-joined, may be empty)
#   error:empty
#   error:unexpected_token:<acc>
#   error:mixed_script:<acc>                            (the explanation text is not compared -
#                                                        the port simplifies it, see the module)

output_file = Path.join(__DIR__, "verification_elixir.txt")

classes_file = Path.join(__DIR__, "classes_elixir.txt")
scriptsets_file = Path.join(__DIR__, "scriptsets_elixir.txt")

usable =
  classes_file
  |> File.stream!()
  |> Enum.flat_map(fn line ->
    case String.split(String.trim(line), ":", parts: 3) do
      [codepoint, "error", "0"] when codepoint != "" -> []
      [codepoint, _start, _continues] -> [String.to_integer(codepoint)]
    end
  end)

IO.puts("Usable codepoints: #{length(usable)}")

unusable_sample =
  0..0x10FFFF
  |> Enum.take_every(97)
  |> Enum.reject(&(&1 in MapSet.new(usable)))

signature_reps =
  scriptsets_file
  |> File.stream!()
  |> Enum.reduce(%{}, fn line, acc ->
    case String.split(String.trim(line), ":", parts: 2) do
      [_codepoint, "-"] ->
        acc

      [codepoint, signature] ->
        Map.update(acc, signature, [String.to_integer(codepoint)], fn reps ->
          if length(reps) < 2, do: reps ++ [String.to_integer(codepoint)], else: reps
        end)
    end
  end)
  |> Map.values()

IO.puts("Script signature groups: #{length(signature_reps)}")

cross_script_pairs =
  for reps1 <- signature_reps,
      reps2 <- signature_reps,
      codepoint1 <- reps1,
      codepoint2 <- reps2,
      variant <- [[codepoint1, codepoint2], [codepoint1, ?_, codepoint2]] do
    variant
  end

app_names =
  for app <- [:elixir, :ex_unit, :hologram, :kernel, :logger, :stdlib],
      {:ok, modules} = :application.get_key(app, :modules),
      module <- modules,
      match?({:module, _mod}, :code.ensure_loaded(module)),
      name <- [module | Enum.map(module.module_info(:exports), fn {f, _a} -> f end)],
      uniq: true do
    Atom.to_charlist(name)
  end

IO.puts("Real-world names: #{length(app_names)}")

inputs =
  Enum.map(usable, &[&1]) ++
    Enum.map(usable, &[?_, &1]) ++
    Enum.map(unusable_sample, &[?_, &1]) ++
    cross_script_pairs ++
    app_names

inputs = Enum.uniq(inputs)

IO.puts("Total inputs: #{length(inputs)}")

serialize_result = fn
  {kind, acc, rest, length, ascii?, special} ->
    "ok:#{kind}:#{Enum.join(acc, ",")}:#{Enum.join(rest, ",")}:#{length}:#{ascii?}:#{Enum.join(special, ",")}"

  {:error, :empty} ->
    "error:empty"

  {:error, {:unexpected_token, acc}} ->
    "error:unexpected_token:#{Enum.join(acc, ",")}"

  {:error, {:mixed_script, acc, _explanation}} ->
    "error:mixed_script:#{Enum.join(acc, ",")}"
end

output =
  Enum.map_join(inputs, "\n", fn input ->
    "#{Enum.join(input, ",")}|#{serialize_result.(String.Tokenizer.tokenize(input))}"
  end)

File.write!(output_file, output)

IO.puts("Verification data written to #{output_file}")
