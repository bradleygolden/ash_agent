defmodule AshAgent.MixProject do
  use Mix.Project

  @version "0.1.0"
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

  def application do
    [
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
      {:ash_baml, path: "../ash_baml", only: :test},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.16", only: :test}
    ]
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
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md documentation)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      before_closing_head_tag: fn
        :html ->
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.0/dist/mermaid.min.js"></script>
          <script>
            document.addEventListener("DOMContentLoaded", function () {
              mermaid.initialize({
                startOnLoad: false,
                theme: document.body.className.includes("dark") ? "dark" : "default"
              });
              let id = 0;
              for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
                const preEl = codeEl.parentElement;
                const graphDefinition = codeEl.textContent;
                const graphEl = document.createElement("div");
                const graphId = "mermaid-graph-" + id++;
                mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                  graphEl.innerHTML = svg;
                  bindFunctions?.(graphEl);
                  preEl.insertAdjacentElement("afterend", graphEl);
                  preEl.remove();
                });
              }
            });
          </script>
          """

        _ ->
          ""
      end
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md": [title: "Changelog"],
      "documentation/tutorials/getting-started.md": [title: "Getting Started"],
      "documentation/topics/overview.md": [title: "Overview"]
    ]
  end

  defp groups_for_extras do
    [
      Tutorials: ~r'documentation/tutorials',
      Topics: ~r'documentation/topics',
      "DSL Reference": ~r'documentation/dsls'
    ]
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
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
