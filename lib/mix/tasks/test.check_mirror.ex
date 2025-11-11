defmodule Mix.Tasks.Test.CheckMirror do
  @moduledoc """
  Validates that test files mirror lib files according to AGENTS.md guidelines.

  ## Usage

      mix test.check_mirror

  ## What it checks

  - Every lib/ash_agent/**/*.ex file has a corresponding test/ash_agent/**/*_test.exs
  - No orphaned test files exist (test files without corresponding lib files)
  - Special exceptions: Mix tasks, transformers, and support files don't require tests

  ## Error messages

  This task provides clear, actionable error messages for AI agents when
  test structure doesn't match lib structure per AGENTS.md:

  > Keep unit tests in `test/ash_agent`, mirroring `lib/` structure with
  > `<filename>_test.exs`

  """

  use Mix.Task

  @shortdoc "Check that test files mirror lib files"

  @impl Mix.Task
  def run(_args) do
    lib_files = find_lib_files()
    test_files = find_test_files()

    missing_tests = find_missing_tests(lib_files)
    orphaned_tests = find_orphaned_tests(test_files, lib_files)

    case {missing_tests, orphaned_tests} do
      {[], []} ->
        Mix.shell().info("✓ All test files properly mirror lib files")
        :ok

      {missing, orphaned} ->
        print_errors(missing, orphaned)
        Mix.raise("Test structure does not mirror lib structure. See errors above.")
    end
  end

  defp find_lib_files do
    Path.wildcard("lib/ash_agent/**/*.ex")
    |> Enum.reject(&should_skip_lib_file?/1)
    |> Enum.map(&normalize_path/1)
  end

  defp find_test_files do
    Path.wildcard("test/ash_agent/**/*_test.exs")
    |> Enum.map(&normalize_path/1)
  end

  defp should_skip_lib_file?(path) do
    cond do
      String.contains?(path, "/mix/tasks/") -> true
      String.ends_with?(path, ".Domain.ex") -> true
      true -> false
    end
  end

  defp normalize_path(path) do
    path
    |> String.replace_prefix("lib/", "")
    |> String.replace_prefix("test/", "")
  end

  defp find_missing_tests(lib_files) do
    Enum.reduce(lib_files, [], fn lib_file, acc ->
      expected_test = lib_to_test_path(lib_file)

      if File.exists?("test/#{expected_test}") do
        acc
      else
        [{lib_file, expected_test} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp find_orphaned_tests(test_files, lib_files) do
    lib_paths_set = MapSet.new(lib_files)

    Enum.reduce(test_files, [], fn test_file, acc ->
      expected_lib = test_to_lib_path(test_file)

      if MapSet.member?(lib_paths_set, expected_lib) do
        acc
      else
        [{test_file, expected_lib} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp lib_to_test_path(lib_path) do
    lib_path
    |> String.replace_suffix(".ex", "_test.exs")
  end

  defp test_to_lib_path(test_path) do
    test_path
    |> String.replace_suffix("_test.exs", ".ex")
  end

  defp print_errors(missing_tests, orphaned_tests) do
    if missing_tests != [] do
      Mix.shell().error("\n❌ Missing test files (lib files without corresponding tests):\n")

      Enum.each(missing_tests, fn {lib_file, expected_test} ->
        Mix.shell().error("  lib/#{lib_file}")
        Mix.shell().error("    → Expected: test/#{expected_test}")
        Mix.shell().error("    → Action: Create test file at test/#{expected_test}\n")
      end)

      Mix.shell().error(
        "Per AGENTS.md: \"Keep unit tests in test/ash_agent, mirroring lib/ structure\""
      )
    end

    if orphaned_tests != [] do
      Mix.shell().error("\n❌ Orphaned test files (tests without corresponding lib files):\n")

      Enum.each(orphaned_tests, fn {test_file, expected_lib} ->
        Mix.shell().error("  test/#{test_file}")
        Mix.shell().error("    → Expected lib file: lib/#{expected_lib}")

        Mix.shell().error(
          "    → Action: Either create lib/#{expected_lib} or remove test/#{test_file}\n"
        )
      end)
    end

    Mix.shell().error("\n📖 Reference: See AGENTS.md testing guidelines")
  end
end
