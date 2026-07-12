defmodule Hueworks.Control.Operation do
  @moduledoc false

  alias Hueworks.Control.{Transition, TransitionPolicy}

  @type origin :: :manual | :presence | :circadian | :scene_activation | atom()
  @type t :: %__MODULE__{
          id: integer(),
          origin: origin(),
          transition_policy: TransitionPolicy.t(),
          trace: map() | nil
        }

  @enforce_keys [:id, :origin, :transition_policy]
  defstruct [:id, :origin, :transition_policy, :trace]

  def new(opts \\ []) when is_list(opts) do
    origin = Keyword.get(opts, :origin, :manual)

    %__MODULE__{
      id: Keyword.get(opts, :operation_id, System.unique_integer([:positive, :monotonic])),
      origin: origin,
      transition_policy: transition_policy(origin, opts),
      trace: Keyword.get(opts, :trace)
    }
  end

  def scene_activation(scene, opts \\ []) when is_list(opts) do
    new(
      origin: :scene_activation,
      transition_policy:
        TransitionPolicy.scene_activation(scene, Keyword.get(opts, :transition_ms)),
      trace: Keyword.get(opts, :trace)
    )
  end

  defp policy_for(:circadian), do: TransitionPolicy.circadian()
  defp policy_for(_origin), do: TransitionPolicy.manual()

  # Preserve the existing direct planner override while routing all new work
  # through the typed policy carried by the operation.
  defp transition_policy(origin, opts) do
    case Keyword.get(opts, :transition_policy) do
      %TransitionPolicy{} = policy ->
        policy

      _ ->
        policy = policy_for(origin)

        case Transition.transition_ms(opts) do
          duration_ms when is_integer(duration_ms) -> %{policy | duration_ms: duration_ms}
          _ -> policy
        end
    end
  end
end
