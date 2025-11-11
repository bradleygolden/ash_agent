defmodule AshAgent.ContextMetadataTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context

  describe "mark_as_summarized/2" do
    test "adds all metadata fields to iteration" do
      iteration = %{number: 1, messages: []}

      summarized = Context.mark_as_summarized(iteration, "User asked about weather")

      assert %{metadata: metadata} = summarized
      assert metadata.summarized == true
      assert metadata.summary == "User asked about weather"
      assert %DateTime{} = metadata.summarized_at
    end

    test "works on iteration without existing metadata field" do
      iteration = %{number: 1}

      summarized = Context.mark_as_summarized(iteration, "Test summary")

      assert %{metadata: metadata} = summarized
      assert metadata.summarized == true
      assert metadata.summary == "Test summary"
    end

    test "preserves existing metadata fields" do
      iteration = %{metadata: %{custom_field: "preserved", other: 42}}

      summarized = Context.mark_as_summarized(iteration, "New summary")

      assert summarized.metadata.custom_field == "preserved"
      assert summarized.metadata.other == 42
      assert summarized.metadata.summarized == true
      assert summarized.metadata.summary == "New summary"
    end

    test "overwrites previous summarization" do
      iteration = %{
        metadata: %{
          summarized: true,
          summary: "Old summary",
          summarized_at: DateTime.from_unix!(1_000_000)
        }
      }

      summarized = Context.mark_as_summarized(iteration, "New summary")

      assert summarized.metadata.summary == "New summary"

      assert DateTime.compare(summarized.metadata.summarized_at, iteration.metadata.summarized_at) ==
               :gt
    end

    test "returns new iteration (immutability)" do
      iteration = %{metadata: %{}}

      summarized = Context.mark_as_summarized(iteration, "Summary")

      refute Map.has_key?(iteration.metadata, :summarized)
      assert summarized.metadata.summarized == true
    end
  end

  describe "is_summarized?/1" do
    test "returns true for summarized iteration" do
      iteration = %{metadata: %{summarized: true}}

      assert Context.is_summarized?(iteration)
    end

    test "returns false for unsummarized iteration" do
      iteration = %{metadata: %{}}

      refute Context.is_summarized?(iteration)
    end

    test "returns false when summarized is false" do
      iteration = %{metadata: %{summarized: false}}

      refute Context.is_summarized?(iteration)
    end

    test "returns false when metadata field is missing" do
      iteration = %{number: 1}

      refute Context.is_summarized?(iteration)
    end

    test "returns false for empty iteration map" do
      iteration = %{}

      refute Context.is_summarized?(iteration)
    end
  end

  describe "get_summary/1" do
    test "retrieves summary from summarized iteration" do
      iteration = %{metadata: %{summarized: true, summary: "Weather query"}}

      assert Context.get_summary(iteration) == "Weather query"
    end

    test "returns nil for unsummarized iteration" do
      iteration = %{metadata: %{}}

      assert Context.get_summary(iteration) == nil
    end

    test "returns nil when metadata field is missing" do
      iteration = %{number: 1}

      assert Context.get_summary(iteration) == nil
    end

    test "returns nil for empty iteration" do
      iteration = %{}

      assert Context.get_summary(iteration) == nil
    end

    test "retrieves summary even if summarized flag is false" do
      iteration = %{metadata: %{summarized: false, summary: "Still has summary"}}

      assert Context.get_summary(iteration) == "Still has summary"
    end
  end

  describe "update_iteration_metadata/3" do
    test "adds custom field to metadata" do
      iteration = %{metadata: %{}}

      updated = Context.update_iteration_metadata(iteration, :custom_key, "value")

      assert updated.metadata.custom_key == "value"
    end

    test "works on iteration without existing metadata field" do
      iteration = %{number: 1}

      updated = Context.update_iteration_metadata(iteration, :new_field, 123)

      assert %{metadata: metadata} = updated
      assert metadata.new_field == 123
    end

    test "preserves existing metadata fields" do
      iteration = %{metadata: %{existing: "data", other: 42}}

      updated = Context.update_iteration_metadata(iteration, :new_field, "new")

      assert updated.metadata.existing == "data"
      assert updated.metadata.other == 42
      assert updated.metadata.new_field == "new"
    end

    test "overwrites existing field with same key" do
      iteration = %{metadata: %{field: "old value"}}

      updated = Context.update_iteration_metadata(iteration, :field, "new value")

      assert updated.metadata.field == "new value"
    end

    test "supports various value types" do
      iteration = %{metadata: %{}}

      # String value
      updated1 = Context.update_iteration_metadata(iteration, :string, "text")
      assert updated1.metadata.string == "text"

      # Integer value
      updated2 = Context.update_iteration_metadata(iteration, :int, 42)
      assert updated2.metadata.int == 42

      # Map value
      updated3 = Context.update_iteration_metadata(iteration, :map, %{nested: true})
      assert updated3.metadata.map == %{nested: true}

      # List value
      updated4 = Context.update_iteration_metadata(iteration, :list, [1, 2, 3])
      assert updated4.metadata.list == [1, 2, 3]
    end

    test "returns new iteration (immutability)" do
      iteration = %{metadata: %{}}

      updated = Context.update_iteration_metadata(iteration, :new_field, "value")

      refute Map.has_key?(iteration.metadata, :new_field)
      assert updated.metadata.new_field == "value"
    end
  end

  describe "metadata doesn't affect other iterations" do
    test "marking one iteration doesn't affect another" do
      iteration1 = %{number: 1, metadata: %{}}
      iteration2 = %{number: 2, metadata: %{}}

      summarized1 = Context.mark_as_summarized(iteration1, "Summary 1")

      # iteration2 should be unchanged
      refute Context.is_summarized?(iteration2)
      assert Context.is_summarized?(summarized1)
    end

    test "updating metadata on one iteration doesn't affect another" do
      iteration1 = %{metadata: %{shared: "value"}}
      iteration2 = %{metadata: %{shared: "value"}}

      updated1 = Context.update_iteration_metadata(iteration1, :custom, "data")

      # iteration2 should be unchanged
      refute Map.has_key?(iteration2.metadata, :custom)
      assert updated1.metadata.custom == "data"
    end
  end

  describe "integration with full workflow" do
    test "can mark, check, and retrieve summary" do
      iteration = %{number: 5, messages: []}

      # Mark as summarized
      summarized = Context.mark_as_summarized(iteration, "Complex calculation result")

      # Check if summarized
      assert Context.is_summarized?(summarized)

      # Retrieve summary
      summary = Context.get_summary(summarized)
      assert summary == "Complex calculation result"

      # Add custom metadata
      with_custom = Context.update_iteration_metadata(summarized, :processed, true)

      # All metadata should be present
      assert with_custom.metadata.summarized == true
      assert with_custom.metadata.summary == "Complex calculation result"
      assert with_custom.metadata.processed == true
    end
  end
end
