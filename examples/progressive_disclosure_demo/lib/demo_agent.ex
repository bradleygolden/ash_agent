defmodule ProgressiveDisclosureDemo.DemoAgent do
  @moduledoc """
  Demo agent with tools that return large results.

  This agent demonstrates Progressive Disclosure by:
  1. Having tools that return large amounts of data
  2. Using PDHooks to process those results
  3. Maintaining context across multiple iterations
  """

  use Ash.Resource,
    domain: ProgressiveDisclosureDemo.Domain,
    extensions: [AshAgent.Resource]

  agent do
    client("mock:test")
    hooks(ProgressiveDisclosureDemo.PDHooks)
    max_iterations(10)

    tools do
      tool :get_large_dataset do
        description("Returns a large dataset (~10KB) for processing")

        function({ProgressiveDisclosureDemo.Tools, :get_large_dataset, []})
      end

      tool :get_user_list do
        description("Returns a list of 100 user records")

        function({ProgressiveDisclosureDemo.Tools, :get_user_list, []})
      end

      tool :get_log_data do
        description("Returns verbose log data")

        function({ProgressiveDisclosureDemo.Tools, :get_log_data, []})
      end
    end
  end
end

defmodule ProgressiveDisclosureDemo.Domain do
  @moduledoc false

  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    allow_unregistered?(true)
  end
end

defmodule ProgressiveDisclosureDemo.Tools do
  @moduledoc """
  Tools that return large results for demonstration.
  """

  def get_large_dataset do
    data = """
    #{String.duplicate("LARGE DATA CHUNK - This is a substantial piece of data that represents typical large tool results. ", 100)}

    Dataset Information:
    - Total Records: 10,000
    - Size: ~10KB
    - Format: JSON-like structure
    - Contains: User activity logs, timestamps, metadata

    Sample Records:
    #{Enum.map_join(1..50, "\n", fn i -> "  Record #{i}: {id: #{i}, timestamp: 2024-01-#{rem(i, 28) + 1}, action: 'page_view', user_id: #{i * 100}}" end)}

    Summary Statistics:
    - Average session duration: 5.2 minutes
    - Peak activity hours: 14:00-16:00 UTC
    - Most common actions: page_view (45%), click (30%), scroll (25%)

    Additional Metadata:
    #{String.duplicate("metadata_field_#{:rand.uniform(1000)}: value, ", 100)}
    """

    {:ok, data}
  end

  def get_user_list do
    users =
      Enum.map(1..100, fn i ->
        %{
          id: i,
          name: "User #{i}",
          email: "user#{i}@example.com",
          created_at: "2024-01-#{rem(i, 28) + 1}",
          preferences: %{
            theme: Enum.random(["light", "dark", "auto"]),
            language: Enum.random(["en", "es", "fr"]),
            notifications: Enum.random([true, false])
          },
          metadata: %{
            last_login: "2024-11-#{rem(i, 30) + 1}",
            login_count: :rand.uniform(1000),
            account_status: "active"
          }
        }
      end)

    {:ok, users}
  end

  def get_log_data do
    logs =
      Enum.map_join(1..200, "\n", fn i ->
        timestamp = "2024-11-10T#{rem(i, 24)}:#{rem(i, 60)}:#{rem(i, 60)}"
        level = Enum.random(["INFO", "WARN", "ERROR", "DEBUG"])
        message = "Log entry #{i}: " <> String.duplicate("detailed information ", 10)
        "#{timestamp} [#{level}] #{message}"
      end)

    {:ok, logs}
  end
end
