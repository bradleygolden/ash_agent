defmodule AshAgent.Tools.AshActionTest do
  use ExUnit.Case, async: true

  alias AshAgent.Tools.AshAction

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false
      attribute :email, :string
    end

    actions do
      default_accept [:name, :email]
      defaults [:read, :destroy, :create, :update]

      read :get_by_name do
        argument :name, :string, allow_nil?: false
        filter expr(name == ^arg(:name))
      end

      update :update_email do
        accept [:email]
      end
    end

    code_interface do
      define :create
      define :get_by_name, args: [:name]
      define :update_email
      define :read
    end
  end

  describe "new/1" do
    test "creates a new AshAction tool with required fields" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create
        )

      assert tool.name == :create_user
      assert tool.description == "Creates a new user"
      assert tool.resource == TestResource
      assert tool.action_name == :create
      assert tool.parameters == []
    end

    test "accepts optional parameters" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [
            [name: :name, type: :string, required: true],
            [name: :email, type: :string, required: false]
          ]
        )

      assert length(tool.parameters) == 2
    end
  end

  describe "Tool behavior implementation" do
    test "name/0 returns :ash_action" do
      assert AshAction.name() == :ash_action
    end

    test "description/0 returns tool description" do
      assert AshAction.description() == "Executes an Ash action"
    end

    test "schema/0 returns basic schema structure" do
      schema = AshAction.schema()

      assert schema.name == "ash_action"
      assert schema.description == "Executes an Ash action"
      assert schema.parameters.type == :object
    end
  end

  describe "execute/2 with create action" do
    test "successfully creates a resource" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [
            [name: :name, type: :string, required: true],
            [name: :email, type: :string, required: false]
          ]
        )

      args = %{name: "Alice", email: "alice@example.com"}
      context = %{tool: tool, actor: nil}

      assert {:ok, result} = AshAction.execute(args, context)
      assert result.name == "Alice"
      assert result.email == "alice@example.com"
    end

    test "handles string keys in arguments" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{"name" => "Bob"}
      context = %{tool: tool, actor: nil}

      assert {:ok, result} = AshAction.execute(args, context)
      assert result.name == "Bob"
    end

    test "returns error when required parameters are missing" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{email: "charlie@example.com"}
      context = %{tool: tool, actor: nil}

      assert {:error, error_msg} = AshAction.execute(args, context)
      assert error_msg =~ "Missing required parameters"
      assert error_msg =~ ":name"
    end
  end

  describe "execute/2 with read action" do
    setup do
      {:ok, user} = TestResource.create(%{name: "TestUser", email: "test@example.com"})
      %{user: user}
    end

    test "successfully reads a resource with arguments", %{user: user} do
      tool =
        AshAction.new(
          name: :get_user,
          description: "Get user by name",
          resource: TestResource,
          action_name: :get_by_name,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{name: user.name}
      context = %{tool: tool, actor: nil}

      assert {:ok, results} = AshAction.execute(args, context)
      assert is_list(results)
      assert length(results) == 1
      assert hd(results).name == user.name
    end

    test "returns empty list when no resources match" do
      tool =
        AshAction.new(
          name: :get_user,
          description: "Get user by name",
          resource: TestResource,
          action_name: :get_by_name,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{name: "NonExistent"}
      context = %{tool: tool, actor: nil}

      assert {:ok, results} = AshAction.execute(args, context)
      assert results == []
    end
  end

  describe "execute/2 with update action" do
    setup do
      {:ok, user} = TestResource.create(%{name: "UpdateTest", email: "old@example.com"})
      %{user: user}
    end

    test "successfully updates a resource", %{user: user} do
      tool =
        AshAction.new(
          name: :update_user_email,
          description: "Update user email",
          resource: TestResource,
          action_name: :update,
          parameters: [[name: :email, type: :string, required: true]]
        )

      args = %{email: "new@example.com"}
      context = %{tool: tool, actor: nil, record: user}

      assert {:ok, result} = AshAction.execute(args, context)
      assert result.email == "new@example.com"
      assert result.name == user.name
    end
  end

  describe "execute/2 error handling" do
    test "handles Ash validation errors" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{}
      context = %{tool: tool, actor: nil}

      assert {:error, error_msg} = AshAction.execute(args, context)
      assert error_msg =~ "Missing required parameters"
    end

    test "handles invalid action errors" do
      tool =
        AshAction.new(
          name: :invalid_action,
          description: "Invalid action",
          resource: TestResource,
          action_name: :nonexistent_action
        )

      args = %{}
      context = %{tool: tool, actor: nil}

      assert {:error, error_msg} = AshAction.execute(args, context)
      assert is_binary(error_msg)
    end
  end

  describe "execute/2 with context" do
    test "passes actor through to Ash action" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{name: "ActorTest"}
      actor = %{id: 123}
      context = %{tool: tool, actor: actor}

      assert {:ok, result} = AshAction.execute(args, context)
      assert result.name == "ActorTest"
    end

    test "passes tenant through to Ash action" do
      tool =
        AshAction.new(
          name: :create_user,
          description: "Creates a new user",
          resource: TestResource,
          action_name: :create,
          parameters: [[name: :name, type: :string, required: true]]
        )

      args = %{name: "TenantTest"}
      context = %{tool: tool, actor: nil, tenant: "org-123"}

      assert {:ok, result} = AshAction.execute(args, context)
      assert result.name == "TenantTest"
    end
  end
end
