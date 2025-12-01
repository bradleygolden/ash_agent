defmodule AshAgent.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/bradleygolden/ash_agent"

  def project do
    [
      app: :ash_agent,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      mod: {AshAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:ash, "~> 3.0"},
      {:spark, "~> 2.2"},
      {:req_llm, "~> 1.0"},
      {:solid, "~> 0.15"},

      # Optional dependencies
      {:igniter, "~> 0.3", optional: true},

      # Dev and test dependencies
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.16", only: :test}
    ] ++ ash_baml_dep()
  end

  defp description do
    """
    An Ash Framework extension for building AI agent applications with LLM integration.
    """
  end

  defp package do
    [
      name: :ash_agent,
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Bradley Golden"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_extras do
    []
  end

  defp groups_for_modules do
    [
      Extensions: [
        AshAgent.Resource,
        AshAgent.Domain
      ],
      Introspection: [
        AshAgent.Info
      ],
      Internals: [
        ~r/AshAgent.Transformers/,
        ~r/AshAgent.Verifiers/
      ]
    ]
  end

  defp aliases do
    [
      precommit: [
        "deps.get",
        "deps.compile",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "test --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --exit",
        "deps.audit",
        "dialyzer",
        "docs --warnings-as-errors"
      ],
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "spark.formatter": "spark.formatter --extensions AshAgent.Resource,AshAgent.Domain"
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp ash_baml_dep do
    if hex_build?() do
      [{:ash_baml, "~> 0.2.0", optional: true}]
    else
      if local_dep?(:ash_baml) do
        [{:ash_baml, in_umbrella: true}]
      else
        [{:ash_baml, "~> 0.2.0", optional: true}]
      end
    end
  end

  defp hex_build?, do: System.get_env("HEX_BUILD") == "true"

  defp local_dep?(app) do
    app
    |> to_string()
    |> then(&Path.expand("../#{&1}/mix.exs", __DIR__))
    |> File.exists?()
  end
end
